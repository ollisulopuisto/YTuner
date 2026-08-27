unit my_stations;

// Retuner : Custom stations list files support unit.
//
// The list a receiver browses is assembled from more than one file: the user's
// own stations.ini (or .yaml), plus whatever country preset files have been
// fetched into the presets cache. They are parsed separately and merged into
// one group here, because everything downstream -- the menu, the ID lookup, the
// web editor -- wants a single published list and should not have to know where
// any given station came from.
//
// ReloadStations is the only way that list is built. Anything that changes an
// input calls it and gets the whole list rebuilt; nothing reloads one file on
// its own, which is what used to make saving in the editor quietly drop every
// preset station until the next restart.

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, syncobjs,
  md5, common, presets;

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

// Where the user's own station file lives. One definition, because Retuner, the
// web editor and the reload path must all mean the same file by it.
function MyStationsFilePath: string;

// Parses one file into a group without publishing anything. Returns the number
// of stations read, or -1 if the file could not be read at all.
function ParseStationsFile(AFileName: string; out AStations: TMyStationsGroup): integer;

// Rebuilds the published list from the user's file plus every cached preset.
function ReloadStations: boolean;

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

function MyStationsFilePath: string;
begin
  Result:=ConfigPath+DirectorySeparator+MyStationsFileName;
end;

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

function ParseMyStationsINI(AFileName: string; out AStations: TMyStationsGroup): integer;
var
  LStr: TStrings;
  i,j,k: integer;
  LMyStationsCount: integer = 0;
  LMSIniTmpValue: string;
  LStations: TMyStationsGroup;
begin
  Result:=-1;
  AStations:=nil;
  LStr:=TStringList.Create;
  try
    with TIniFile.Create(AFileName) do
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
          AStations:=LStations;
          Result:=LMyStationsCount;
        except
          Result:=-1;
        end;
      finally
        Free;
      end;
  finally
    LStr.Free;
  end;
end;

function ParseMyStationsYAML(AFileName: string; out AStations: TMyStationsGroup): integer;
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
  Result:=-1;
  AStations:=nil;
  LStationsFileContent:=TStringList.Create;
  try
    try
      LStationsFileContent.LoadFromFile(AFileName);
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
      AStations:=LStations;
      Result:=LMyStationsCount;
    except
      Result:=-1;
    end;
  finally
    LStationsFileContent.Free;
  end;
end;

function ParseStationsFile(AFileName: string; out AStations: TMyStationsGroup): integer;
begin
  AStations:=nil;
  Result:=-1;
  if not FileExists(AFileName) then
    Exit;
// A preset file is always .ini; only the user's own file gets a choice, and the
// extension is what decides which parser reads it.
  if SameText(ExtractFileExt(AFileName),'.ini') then
    Result:=ParseMyStationsINI(AFileName,AStations)
  else if SameText(ExtractFileExt(AFileName),'.yaml') or SameText(ExtractFileExt(AFileName),'.yml') then
    Result:=ParseMyStationsYAML(AFileName,AStations)
  else
    Logging(ltError, string.Join(' ',['My stations:',AFileName,'has no extension this can read']));
end;

// Categories are matched by name, so a preset's "Yle" folds into a user's "Yle"
// rather than appearing twice in the menu. Within a category a station already
// present is skipped -- the ID is a hash of name and URL, so the same station
// listed in both files is the same entry, not two.
function MergeInto(var ATarget: TMyStationsGroup; const ASource: TMyStationsGroup): integer;
var
  i,j,k: integer;
  LCat: integer;
  LFound: boolean;
begin
  Result:=0;
  for i:=0 to Length(ASource)-1 do
    begin
      LCat:=-1;
      for j:=0 to Length(ATarget)-1 do
        if SameText(ATarget[j].MSCategory,ASource[i].MSCategory) then
          begin
            LCat:=j;
            Break;
          end;
      if LCat<0 then
        begin
          LCat:=Length(ATarget);
          SetLength(ATarget,LCat+1);
          ATarget[LCat].MSCategory:=ASource[i].MSCategory;
        end;
      for j:=0 to Length(ASource[i].MSStations)-1 do
        begin
          LFound:=False;
          for k:=0 to Length(ATarget[LCat].MSStations)-1 do
            if ATarget[LCat].MSStations[k].MSID=ASource[i].MSStations[j].MSID then
              begin
                LFound:=True;
                Break;
              end;
          if not LFound then
            begin
              SetLength(ATarget[LCat].MSStations,Length(ATarget[LCat].MSStations)+1);
              ATarget[LCat].MSStations[High(ATarget[LCat].MSStations)]:=ASource[i].MSStations[j];
              Result:=Result+1;
            end;
        end;
    end;
end;

function ReloadStations: boolean;
var
  LMerged, LOne: TMyStationsGroup;
  LFiles: TStringArray;
  LExt: string;
  i, LCount, LOwn, LPreset: integer;
begin
  LMerged:=nil;
  LOwn:=0;
  LPreset:=0;

  LCount:=ParseStationsFile(MyStationsFilePath,LOne);
  if LCount>=0 then
    LOwn:=MergeInto(LMerged,LOne)
  else
    if FileExists(MyStationsFilePath) then
      begin
        LExt:=UpperCase(ExtractFileExt(MyStationsFilePath));
        Logging(ltError, LExt.TrimLeft(['.'])+MSG_FILE_LOAD_ERROR);
      end;

// Presets come second so the user's own categories lead the menu and their
// version of a station wins any tie.
  LFiles:=PresetsCachedFiles;
  for i:=0 to Length(LFiles)-1 do
    begin
      LCount:=ParseStationsFile(LFiles[i],LOne);
      if LCount>=0 then
        LPreset:=LPreset+MergeInto(LMerged,LOne)
      else
        Logging(ltError, string.Join(' ',['Presets:',MSG_ERROR,'reading',LFiles[i]]));
    end;

  Result:=(LOwn+LPreset)>0;
  if Result then
    begin
      PublishMyStations(LMerged);
      if LPreset>0 then
        Logging(ltInfo, MSG_SUCCESSFULLY_LOADED+IntToStr(LOwn+LPreset)+' my '+MSG_STATIONS+
                        ' ('+IntToStr(LPreset)+' from presets)')
      else
        Logging(ltInfo, MSG_SUCCESSFULLY_LOADED+IntToStr(LOwn)+' my '+MSG_STATIONS);
    end
  else
// Publishing the empty list matters: if the file was emptied or went missing,
// leaving the previous list published would serve stations that no longer
// exist anywhere in the configuration.
    begin
      PublishMyStations(LMerged);
      Logging(ltWarning, 'My stations: no stations loaded');
    end;
end;

initialization
  MyStationsLock:=TCriticalSection.Create;

finalization
  MyStationsLock.Free;

end.
