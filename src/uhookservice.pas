unit uHookService;

{$mode delphi}

interface

uses
  Classes, SysUtils, Windows, uHookCommon, MemMap, uKbdDevice;

type

  { THookService }

  THookService = class
    private
      fSharedMemory: TMemMap;
      fSMPtr: PMMFData;
      fHookSet: Boolean;
      procedure InitSharedMemory(pMainFormHandle: THandle);
      function DescribeHookMessage(pMessage: TMessage): String;
      function ConvertHookMessageToKeyStroke(pMessage: TMessage): TKeyStroke;
    public
      constructor Create;
      destructor Destroy; virtual;
      procedure Init(pMainFormHandle: THandle);
      procedure OnHookMessage(var pMessage: TMessage);
  end;

const
  HookLib = 'WinHook.dll';
  cHookLoggerName = 'HOOK';


  function SetHook: Boolean; stdcall; external HookLib;
  function FreeHook: Boolean; stdcall; external HookLib;


implementation

uses
  uGlobals, uDevice;

{ THookService }

procedure THookService.InitSharedMemory(pMainFormHandle: THandle);
begin
  fSMPtr := nil;
  try
    fSharedMemory := TMemMap.Create(MMFName, SizeOf(TMMFData));
    fSMPtr := fSharedMemory.Memory;
  except
    on EMemMapException do
    begin
      Glb.LogError('Can''t create shared memory.', cHookLoggerName);
      fSharedMemory := nil;
    end;
  end;
  if fSMPtr <> nil then
  begin
    fSMPtr^.MainWinHandle := pMainFormHandle;
    fSMPtr^.LmcPID := GetCurrentProcessId;
    fSMPtr^.Debug:=1; // for now
  end;
end;

function THookService.DescribeHookMessage(pMessage: TMessage): String;
var
  lPrevious, lDirection: String;
begin
  if (pMessage.lParam and $80000000 shr 31 > 0) then
    lDirection:='UP'
  else
    lDirection:='DOWN';
  if (pMessage.lParam and $40000000 shr 30 > 0) then
    lPrevious:='DOWN'
  else
    lPrevious:='UP';
  Result := Format('key code %d [%s], repeat %d, scan code %d, extended %d, alt %d, previous %s, direction %s',
    [pMessage.wParam, Glb.DeviceService.KbdDeviceService.GetCharFromVirtualKey(pMessage.wParam),
    pMessage.lParam and $FFFF, pMessage.lParam and $FF0000 shr 16,
    pMessage.lParam and $1000000 shr 24, pMessage.lParam and $20000000 shr 29,
    lPrevious, lDirection]);
end;

function THookService.ConvertHookMessageToKeyStroke(pMessage: TMessage
  ): TKeyStroke;
begin
  Result.DeviceHandle:=0;  // unknown yet
  Result.Device:=nil;  // unknown yet
  Result.VKeyCode:=pMessage.wParam;
  if (pMessage.lParam and $80000000 shr 31 > 0) then
    Result.Direction:=cDirectionUp
  else
    Result.Direction:=cDirectionDown;
end;

constructor THookService.Create;
begin
  fHookSet:=False;
end;

destructor THookService.Destroy;
begin
  if (fHookSet) then
    FreeHook;
end;

procedure THookService.Init(pMainFormHandle: THandle);
begin
  InitSharedMemory(pMainFormHandle);
  if (not fHookSet) then
  begin
    fHookSet := LongBool(SetHook);
  end;
end;

procedure THookService.OnHookMessage(var pMessage: TMessage);
var
  lKS: TKeyStroke;
  lLogKS: TKeyStrokePtr;
begin
  Glb.DebugLog('Hook message: ' + DescribeHookMessage(pMessage), cHookLoggerName);
  lKS := ConvertHookMessageToKeyStroke(pMessage);
  lLogKS := Glb.KeyLogService.AssignDevice(lKS);
  pMessage.Result:=0; // do not block
  if (lKS.DeviceHandle <> 0) then
  begin
    lKS.Device := Glb.DeviceService.GetByHandle(lKS.DeviceHandle) as TKbdDevice;
    if (Glb.LuaEngine.IsKeyHandled(@lKS)) then
    begin
      pMessage.Result:=-1; // block
    end;
  end;
end;

end.
