unit main;

interface
  uses
    DDDK;
    
  const
    DEV_NAME = '\Device\MyDriver';

  function _DriverEntry(pOurDriver:PDRIVER_OBJECT; pOurRegistry:PUNICODE_STRING):NTSTATUS; stdcall;

implementation
var
  pNextDevice: PDEVICE_OBJECT;
  
procedure Unload(pOurDriver:PDRIVER_OBJECT); stdcall;
begin
end;

function IrpPnp(pOurDevice:PDEVICE_OBJECT; pIrp:PIRP):NTSTATUS; stdcall;
var
  psk: PIO_STACK_LOCATION;
  
begin
  psk:= IoGetCurrentIrpStackLocation(pIrp);
  if psk^.MinorFunction = IRP_MN_REMOVE_DEVICE then
  begin
    IoDetachDevice(pNextDevice);
    IoDeleteDevice(pOurDevice);
  end;
  IoSkipCurrentIrpStackLocation(pIrp);
  Result:= IoCallDriver(pNextDevice, pIrp);
end;

function AddDevice(pOurDriver:PDRIVER_OBJECT; pPhyDevice:PDEVICE_OBJECT):NTSTATUS; stdcall;
var
  suDevName: UNICODE_STRING;
  pOurDevice: PDEVICE_OBJECT;
  
begin
  DbgPrint('Hello, world!', []);
  
  RtlInitUnicodeString(@suDevName, DEV_NAME);
  IoCreateDevice(pOurDriver, 0, @suDevName, FILE_DEVICE_UNKNOWN, 0, FALSE, pOurDevice);
  pNextDevice:= IoAttachDeviceToDeviceStack(pOurDevice, pPhyDevice);
  pOurDevice^.Flags:= pOurDevice^.Flags or DO_BUFFERED_IO;
  pOurDevice^.Flags:= pOurDevice^.Flags and not DO_DEVICE_INITIALIZING;
  Result:= STATUS_SUCCESS;
end;

function _DriverEntry(pOurDriver:PDRIVER_OBJECT; pOurRegistry:PUNICODE_STRING):NTSTATUS; stdcall;
begin
  pOurDriver^.MajorFunction[IRP_MJ_PNP]:= @IrpPnp;
  pOurDriver^.DriverExtension^.AddDevice:=@AddDevice;
  pOurDriver^.DriverUnload:=@Unload;
  Result:=STATUS_SUCCESS;
end;
end.
