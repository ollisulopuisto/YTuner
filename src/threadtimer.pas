unit threadtimer;

// Retuner: thread timer unit.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, syncobjs;

type
  TOnTimer = procedure(Sender: TObject);

  TThreadTimer = class(TThread)
  private
    FName: string;
    FInterval: Cardinal;
    FOnTimer: TOnTimer;
    FEvent: TEventObject;
    FEnabled: Boolean;
    FProcessing: Boolean;
    FNeeded: Boolean;
    procedure DoOnTimer;
  protected
    procedure Execute; override;
  public
    property OnTimer: TOnTimer read FOnTimer write FOnTimer;
    property Interval: Cardinal read FInterval write FInterval;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Processing: Boolean read FProcessing write FProcessing;
    property Needed: Boolean read FNeeded write FNeeded;
    procedure StopTimer;
    procedure StartTimer;
// Stops the timer and waits for the worker to finish. The caller owns the
// object afterwards and must free it.
    procedure TerminateTimer;
    constructor Create(AName: string);
    destructor Destroy; override;
  end;

const
  RB_THREAD = 'RBThread';
  MS_THREAD = 'MSThread';
  GT_THREAD = 'GTThread';
  PS_THREAD = 'PSThread';

var
  RBThread, MSThread : TThreadTimer;
  PSThread : TThreadTimer = nil;
  GTThread : TThreadTimer = nil;

implementation

constructor TThreadTimer.Create(AName: string);
begin
  inherited Create(True);  // Suspended = True
  FName:=AName;
  FEvent:=TEventObject.Create(nil,True,False,AName);
  FInterval:=1000;
// Not FreeOnTerminate: shutdown waits for the worker to leave Execute before
// anything is released, so the event cannot be freed underneath it.
  FreeOnTerminate:=False;
  FEnabled:=False;
  FProcessing:=False;
  FNeeded:=False;
end;

destructor TThreadTimer.Destroy;
begin
  FreeAndNil(FEvent);
  inherited Destroy;
end;

procedure TThreadTimer.DoOnTimer;
begin
  if Assigned(FOnTimer) then
    FOnTimer(Self);
end;

procedure TThreadTimer.Execute;
begin
  while not Terminated do
    begin
      FEvent.WaitFor(FInterval);
      if Terminated then
        Break;
      if FEnabled and (not FProcessing) then
        DoOnTimer;
      FEvent.ResetEvent;
    end;
end;

procedure TThreadTimer.StopTimer;
begin
  FEnabled:=False;
//  Self.Suspended:=True;       // Not suitable for *nix.
end;

procedure TThreadTimer.StartTimer;
begin
  FEnabled:=True;
  if Self.Suspended then Start;
end;

procedure TThreadTimer.TerminateTimer;
begin
  FEnabled:=False;
  OnTerminate:=nil;
// Terminated must be set before the worker is woken, otherwise it goes round
// the loop once more and the wake-up is lost.
  Terminate;
  FEvent.SetEvent;
  WaitFor;
end;

end.

