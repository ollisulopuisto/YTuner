unit my_stations;

// Ytuner : Custom stations list files support unit.

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, syncobjs,
  md5, common;

const
  MY_STATIONS_EXT : Array Of AnsiString = ('.ini','.yaml','.yml');
  MY_STATIONS_FILE_NANME = 'stations.ini';
type
  TMyStation = record
                 MSID, MSName, MSURL, MSLogoURL: string;
               end;

  TMyStations = array of TMyStation;

  TMyStationsGroup = array of record
                                MSCategory: string;
                                MSStations: TMyStations;
                              end;

  TMSStation = record
                 Category: string;
                 Station: TMyStation;
               end;

function GetMyStationByID(AID: string): TMSStation;
function ReadMyStationsINIFile(AMyStationsFileName: string): boolean;
function ReadMyStationsYAMLFile(AMyStationsFileName: string): boolean;

// The refresh timer rebuilds the station list on its own thread while request
// threads are reading it. Readers take a snapshot of the array reference, which
// keeps their copy alive when a refresh publishes a replacement.
function GetMyStationsSnapshot: TMyStationsGroup;
procedure PublishMyStations(const AStations: TMyStationsGroup);

var
  MyStationsEnabled: boolean = True;
  MyStationsFileName: string = MY_STATIONS_FILE_NANME;
  MyStationsAutoRefreshPeriod: integer = 0;
  MyStationsFileAge: LongInt = 0;
  MyStationsFileCRC32: LongWord = 0;
  MyStations: TMyStationsGroup;
  MyStationsLock: TCriticalSection;

implementation

function GetMyStationsSnapshot: TMyStationsGroup;
begin
  MyStationsLock.Enter;
  try
    Result:=MyStations;
  finally
    MyStationsLock.Leave;
  end;
end;

procedure PublishMyStations(const AStations: TMyStationsGroup);
begin
  MyStationsLock.Enter;
  try
    MyStations:=AStations;
  finally
    MyStationsLock.Leave;
  end;
end;

function GetMyStationByID(AID: string): TMSStation;
var
  i,j: integer;
  LStations: TMyStationsGroup;
begin
  LStations:=GetMyStationsSnapshot;
  for i:=0 to Length(LStations)-1 do
    for j:=0 to Length(LStations[i].MSStations)-1 do
      if LStations[i].MSStations[j].MSID=AID then
        with Result do
          begin
            Category:=LStations[i].MSCategory;
            Station:=LStations[i].MSStations[j];
            Exit;
          end;
end;

function ReadMyStationsINIFile(AMyStationsFileName: string): boolean;
var
  LStr: TStrings;
  i,j,k: integer;
  LMyStationsCount: integer = 0;
  LMSIniTmpValue: string;
  LStations: TMyStationsGroup;
begin
  Result:=False;
  LStr:=TStringList.Create;
  try
    with TIniFile.Create(AMyStationsFileName) do
      try
        try
          ReadSections(LStr);
          SetLength(LStations,LStr.Count);
          for i:=0 to LStr.Count-1 do
            LStations[i].MSCategory:=LStr[i];
          for i:=0 to Length(LStations)-1 do
            begin
              LStr.Clear;
              ReadSectionRaw(LStations[i].MSCategory,LStr);
              SetLength(LStations[i].MSStations,LStr.Count);
              k:=0;
              for j:=0 to LStr.Count-1 do
                if Length(LStr[j].Split(['=']))>1 then
                  begin
                    with LStations[i].MSStations[k] do
                      begin
                        MSName:=LStr[j].Split(['='])[0].Trim;
                        LMSIniTmpValue:=LStr[j].Substring(LStr[j].IndexOf('=')+1);
                        MSURL:=LMSIniTmpValue.Split(['|'])[0].Trim;
                        If Length(LMSIniTmpValue.Split(['|']))>1 then
                          MSLogoURL:=LMSIniTmpValue.Split(['|'])[1].Trim;
// Crash on old Linux (?!)   MSID:=MY_STATIONS_PREFIX+'_'+MD5Print(MD5String(MSName+MSURL)).Substring(0,12).ToUpper;
                        MSID:=MY_STATIONS_PREFIX+'_'+MD5Print(MD5String(MSName+MSURL)).Substring(0,12);
                        MSID:=MSID.ToUpper;
                      end;
                    k:=k+1;
                  end;
// Lines without '=' reserved a slot they never filled, so they surfaced as
// blank entries on the AVR and inflated the loaded-stations count.
              SetLength(LStations[i].MSStations,k);
              LMyStationsCount:=LMyStationsCount+k;
            end;
          Result:=(LMyStationsCount>0);
        except
          Result:=False;
        end;
      finally
        Free;
      end;
  finally
    LStr.Free;
    if Result then
      begin
        PublishMyStations(LStations);
        Logging(ltInfo, MSG_SUCCESSFULLY_LOADED+IntToStr(LMyStationsCount)+' my '+MSG_STATIONS);
      end
    else
      Logging(ltError, 'INI'+MSG_FILE_LOAD_ERROR)
  end;
end;

function ReadMyStationsYAMLFile(AMyStationsFileName: string): boolean;
const
  LSeparators: array of string = (': ','|');
var
  LStationsFileContent: TStrings;
  i: integer = 0;
  j: integer = 0;
  c: integer = 0;
  LMyStationsCount: integer = 0;
  LStations: TMyStationsGroup;
  LParts: TStringArray;
begin
  Result:=False;
  LStationsFileContent:=TStringList.Create;
  try
    try
      LStationsFileContent.LoadFromFile(AMyStationsFileName);
      while i<LStationsFileContent.Count do
        begin
          if LStationsFileContent.Strings[i].EndsWith(':') then
            begin
              SetLength(LStations,c+1);
              LStations[c].MSCategory:=LStationsFileContent.Strings[i].Trim.TrimRight(':');
              c:=c+1;
              j:=0;
            end
          else
// A station line before the first category header used to index LStations[-1].
            if (c>0) and (LStationsFileContent.Strings[i].Contains(': ')) then
              begin
                LParts:=LStationsFileContent.Strings[i].Split(LSeparators);
                if Length(LParts)>1 then
                  begin
                    SetLength(LStations[c-1].MSStations,j+1);
                    with LStations[c-1].MSStations[j] do
                      begin
                        MSName:=LParts[0].Trim;
                        MSURL:=LParts[1].Trim;
                        if Length(LParts)>2 then
                          MSLogoURL:=LParts[2].Trim;
// Crash on old Linux (?!)   MSID:=MY_STATIONS_PREFIX+'_'+MD5Print(MD5String(MSName+MSURL)).Substring(0,12).ToUpper;
                        MSID:=MY_STATIONS_PREFIX+'_'+MD5Print(MD5String(MSName+MSURL)).Substring(0,12);
                        MSID:=MSID.ToUpper;
                      end;
                    LMyStationsCount:=LMyStationsCount+1;
                    j:=j+1;
                  end;
              end;
          i:=i+1;
        end;
      Result:=(LMyStationsCount>0);
    except
      Result:=False;
    end;
  finally
    LStationsFileContent.Free;
    if Result then
      begin
        PublishMyStations(LStations);
        Logging(ltInfo, MSG_SUCCESSFULLY_LOADED+IntToStr(LMyStationsCount)+' my '+MSG_STATIONS);
      end
    else
      Logging(ltError, 'YAML'+MSG_FILE_LOAD_ERROR)
  end;
end;

initialization
  MyStationsLock:=TCriticalSection.Create;

finalization
  MyStationsLock.Free;

end.

