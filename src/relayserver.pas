unit relayserver;

// YTuner: HTTP relay for stations these AVRs cannot fetch themselves.
//
// A growing share of stations are HTTPS-only and vTuner-era firmware has no
// TLS, so the existing "all-as-http" setting -- which only rewrites the scheme
// and hopes the station still answers on port 80 -- increasingly fails. With
// the relay enabled YTuner fetches such a stream itself and re-serves it over
// plain HTTP.
//
// This needs its own listener rather than a route on the web server: fcl-web
// frames a response from ContentLength and reads the content stream exactly
// once, so it cannot emit an open-ended stream. Here the socket is ours, so
// bytes are forwarded as they arrive and the connection lasts as long as the
// listener keeps playing.

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, ssockets,
  fphttpclient, common;

const
  RELAY_PORT = 8888;
  RELAY_PATH = '/relay';
  RELAY_SERVICE = 'Relay Service';
  RELAY_REQUEST_MAX = 4096;

type
// Resolves a station id to the URL to pull from. Supplied by httpserver so this
// unit does not have to depend on it.
  TRelayResolveURL = function(const AID: string): string;

// Everything TFPHTTPClient writes here goes straight out to the AVR, so an
// endless stream is forwarded chunk by chunk and never accumulates.
  TRelayForwardStream = class(TStream)
  private
    FTarget: TStream;
  public
    constructor Create(ATarget: TStream);
    function Write(const Buffer; Count: Longint): Longint; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

var
  RelayHTTPS: boolean = False;
  RelayPort: integer = RELAY_PORT;
  OnRelayResolveURL: TRelayResolveURL = nil;

function StartRelayServer: boolean;
procedure StopRelayServer;
function RelayURLFor(const AStationID: string): string;
function NeedsRelay(const AURL: string): boolean;

implementation

type
  TRelayListener = class(TThread)
  private
    FServer: TInetServer;
    procedure HandleConnect(Sender: TObject; Data: TSocketStream);
  protected
    procedure Execute; override;
  public
    destructor Destroy; override;
    procedure Stop;
  end;

var
  RelayListener: TRelayListener = nil;

constructor TRelayForwardStream.Create(ATarget: TStream);
begin
  inherited Create;
  FTarget:=ATarget;
end;

function TRelayForwardStream.Write(const Buffer; Count: Longint): Longint;
begin
// A write that fails means the AVR hung up -- changed station or powered off.
// Letting it raise unwinds the fetch, which is exactly what should happen.
  FTarget.WriteBuffer(Buffer,Count);
  Result:=Count;
end;

function TRelayForwardStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result:=0;
end;

function TRelayForwardStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result:=0;
end;

function NeedsRelay(const AURL: string): boolean;
begin
  Result:=RelayHTTPS and AURL.ToLower.StartsWith('https://');
end;

function RelayURLFor(const AStationID: string): string;
begin
  Result:='http://'+URLHost+':'+RelayPort.ToString+RELAY_PATH+'?'+PATH_PARAM_ID+'='+AStationID;
end;

// Pulls the station id out of the request line, e.g. GET /relay?id=RB_X HTTP/1.1
function RelayRequestedID(const ARequestLine: string): string;
var
  LTarget: string;
begin
  Result:='';
  if Length(ARequestLine.Split([' ']))<2 then
    Exit;
  LTarget:=ARequestLine.Split([' '])[1];
  if not LTarget.StartsWith(RELAY_PATH) then
    Exit;
  if not LTarget.Contains(PATH_PARAM_ID+'=') then
    Exit;
  Result:=LTarget.Substring(LTarget.IndexOf(PATH_PARAM_ID+'=')+Length(PATH_PARAM_ID)+1).Split(['&'])[0];
end;

function ReadRequestLine(ASocket: TStream): string;
var
  LByte: Byte = 0;
  LCount: integer = 0;
begin
  Result:='';
  while LCount<RELAY_REQUEST_MAX do
    begin
      if ASocket.Read(LByte,1)<>1 then
        Break;
      Inc(LCount);
      if LByte=10 then
        Break;
      if LByte<>13 then
        Result:=Result+Chr(LByte);
    end;
end;

procedure SendRelayStatus(ASocket: TStream; const AStatus, AExtraHeaders: string);
var
  LHead: string;
begin
  LHead:='HTTP/1.0 '+AStatus+#13#10
        +'Server: '+YTUNER_USER_AGENT+'/'+APP_VERSION+#13#10
        +AExtraHeaders
        +'Connection: close'+#13#10#13#10;
  ASocket.WriteBuffer(LHead[1],Length(LHead));
end;

procedure RelayStation(ASocket: TSocketStream);
var
  LRequestLine, LID, LURL: string;
  LForward: TRelayForwardStream;
begin
  LRequestLine:=ReadRequestLine(ASocket);
  LID:=RelayRequestedID(LRequestLine);
  if LID.IsEmpty or (not Assigned(OnRelayResolveURL)) then
    begin
      SendRelayStatus(ASocket,'404 Not Found','');
      Exit;
    end;
  LURL:=OnRelayResolveURL(LID);
  if ResolvePlaylists and LooksLikePlaylist(LURL) then
    LURL:=ResolveStreamURL(LURL);
  if LURL.IsEmpty then
    begin
      Logging(ltWarning, string.Join(' ',[RELAY_SERVICE+':',MSG_STATIONS,MSG_NOT_FOUND,LID]));
      SendRelayStatus(ASocket,'404 Not Found','');
      Exit;
    end;

  Logging(ltDebug, string.Join(' ',[RELAY_SERVICE+':',LID,'->',LURL]));
  LForward:=TRelayForwardStream.Create(ASocket);
  try
    with TFPHTTPClient.Create(nil) do
      try
        AllowRedirect:=True;
        ConnectTimeout:=HTTP_CLIENT_CONNECT_TIMEOUT;
// No IOTimeout: a live stream is meant to stay open indefinitely, and the read
// only ends when the station stops or the AVR disconnects.
        IOTimeout:=0;
        AddHeader(HTTP_HEADER_USER_AGENT,YTUNER_USER_AGENT+'/'+APP_VERSION);
        try
// Headers go out before the fetch so the AVR starts consuming immediately; the
// content type is the common case for these streams and is what the device
// expects to be told.
          SendRelayStatus(ASocket,'200 OK','Content-Type: audio/mpeg'+#13#10);
          Get(LURL,LForward);
        except
          on E: Exception do
            Logging(ltDebug, string.Join(' ',[RELAY_SERVICE+':','stream ended',LID,'('+E.Message+')']));
        end;
      finally
        Free;
      end;
  finally
    LForward.Free;
  end;
end;

procedure TRelayListener.HandleConnect(Sender: TObject; Data: TSocketStream);
begin
  try
    try
      RelayStation(Data);
    except
      on E: Exception do
        Logging(ltDebug, string.Join(' ',[RELAY_SERVICE+':',MSG_ERROR,'('+E.Message+')']));
    end;
  finally
    Data.Free;
  end;
end;

procedure TRelayListener.Execute;
begin
  try
    FServer:=TInetServer.Create(RelayPort);
    FServer.OnConnect:=@HandleConnect;
    FServer.Bind;
    FServer.Listen;
    FServer.StartAccepting;
  except
    on E: Exception do
      if not Terminated then
        Logging(ltError, string.Join(' ',[RELAY_SERVICE+':',MSG_ERROR,'('+E.Message+')']));
  end;
end;

procedure TRelayListener.Stop;
begin
  Terminate;
  if Assigned(FServer) then
    FServer.StopAccepting(True);
end;

destructor TRelayListener.Destroy;
begin
  FreeAndNil(FServer);
  inherited Destroy;
end;

function StartRelayServer: boolean;
begin
  Result:=False;
  try
    RelayListener:=TRelayListener.Create(True);
    RelayListener.FreeOnTerminate:=False;
    RelayListener.Start;
    Result:=True;
  except
    on E: Exception do
      Logging(ltError, string.Join(' ',[RELAY_SERVICE+':',MSG_ERROR,'('+E.Message+')']));
  end;
end;

procedure StopRelayServer;
begin
  if Assigned(RelayListener) then
    begin
      RelayListener.Stop;
      FreeAndNil(RelayListener);
    end;
end;

end.
