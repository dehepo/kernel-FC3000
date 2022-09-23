unit main;

interface
  uses
    DDDK;
    
  const
    MAX_THREAD = 3;
    DEV_NAME = '\Device\MyDriver';
    SYM_NAME = '\DosDevices\MyDriver';

  function _DriverEntry(pOurDriver:PDRIVER_OBJECT; pOurRegistry:PUNICODE_STRING):NTSTATUS; stdcall;

implementation
var
  myLock: KSPIN_LOCK;
  pNextDevice: PDEVICE_OBJECT;

procedure RunMe(v:ULONG); stdcall;
var
  c0: ULONG;
  c1: ULONG;
  oldIrql: KIRQL;

begin
  DbgPrint('Thread%d, Locking', [v]);
  KeAcquireSpinLock(@myLock, @oldIrql);
  DbgPrint('Thread%d, Locked', [v]);

  for c0:=0 to 10000 do
    for c1:=0 to 10000 do
      ;

  DbgPrint('Thread%d, Unlocking', [v]);
  KeReleaseSpinLock(@myLock, oldIrql);
  DbgPrint('Thread%d, Unlocked', [v]);
end;

procedure MyThread(pParam:Pointer); stdcall;
var
  tt: LARGE_INTEGER;
 
begin
  tt.HighPart:= tt.HighPart or -1;
  tt.LowPart:= ULONG(-10000000);
  KeDelayExecutionThread(KernelMode, FALSE, @tt);

  RunMe(ULONG(pParam));
  PsTerminateSystemThread(STATUS_SUCCESS);
end;

procedure Unload(pOurDriver:PDRIVER_OBJECT); stdcall;
begin
end;

function IrpPnp(pOurDevice:PDEVICE_OBJECT; pIrp:PIRP):NTSTATUS; stdcall;
var
  psk: PIO_STACK_LOCATION;
  suSymName: UNICODE_STRING;
  
begin
  psk:= IoGetCurrentIrpStackLocation(pIrp);
  if psk^.MinorFunction = IRP_MN_REMOVE_DEVICE then
  begin
    RtlInitUnicodeString(@suSymName, SYM_NAME);
    IoDetachDevice(pNextDevice);
    IoDeleteDevice(pOurDevice);
    IoDeleteSymbolicLink(@suSymName);
  end;
  IoSkipCurrentIrpStackLocation(pIrp);
  Result:= IoCallDriver(pNextDevice, pIrp);
end;

function AddDevice(pOurDriver:PDRIVER_OBJECT; pPhyDevice:PDEVICE_OBJECT):NTSTATUS; stdcall;
var
  suDevName: UNICODE_STRING;
  suSymName: UNICODE_STRING;
  pOurDevice: PDEVICE_OBJECT;
  
begin
  RtlInitUnicodeString(@suDevName, DEV_NAME);
  RtlInitUnicodeString(@suSymName, SYM_NAME);
  IoCreateDevice(pOurDriver, 0, @suDevName, FILE_DEVICE_UNKNOWN, 0, FALSE, pOurDevice);
  pNextDevice:= IoAttachDeviceToDeviceStack(pOurDevice, pPhyDevice);
  pOurDevice^.Flags:= pOurDevice^.Flags or DO_BUFFERED_IO;
  pOurDevice^.Flags:= pOurDevice^.Flags and not DO_DEVICE_INITIALIZING;
  Result:= IoCreateSymbolicLink(@suSymName, @suDevName);
end;

function _DriverEntry(pOurDriver:PDRIVER_OBJECT; pOurRegistry:PUNICODE_STRING):NTSTATUS; stdcall;
var
  cc: ULONG;
  hThread: Handle;
  status: NTSTATUS;

begin
  pOurDriver^.MajorFunction[IRP_MJ_PNP]:= @IrpPnp;
  pOurDriver^.DriverExtension^.AddDevice:=@AddDevice;
  pOurDriver^.DriverUnload:=@Unload;

  KeInitializeSpinLock(@myLock);
  for cc:=0 to (MAX_THREAD-1) do
  begin
    status:= PsCreateSystemThread(@hThread, THREAD_ALL_ACCESS, Nil, Handle(-1), Nil, MyThread, Pointer(cc));
    if NT_SUCCESS(status) then
    begin
      ZwClose(hThread);
    end;
  end;
  Result:=STATUS_SUCCESS;
end;
end.
