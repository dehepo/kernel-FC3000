unit main;

interface
  uses
    DDDK;
    
  const
    DEV_NAME = '\Device\MyDriver';
    SYM_NAME = '\DosDevices\MyDriver';

  function _DriverEntry(pOurDriver:PDRIVER_OBJECT; pOurRegistry:PUNICODE_STRING):NTSTATUS; stdcall;

implementation
var
  pNextDevice: PDEVICE_OBJECT;
  szBuf: array[0..255] of char;
  
procedure Unload(pOurDriver:PDRIVER_OBJECT); stdcall;
begin
end;

function IrpFile(pOurDevice:PDEVICE_OBJECT; pIrp:PIRP):NTSTATUS; stdcall;
var
  len: ULONG;
  psk: PIO_STACK_LOCATION;
  
begin
  len:= 0;
  psk:= IoGetCurrentIrpStackLocation(pIrp);
  case psk^.MajorFunction of
  IRP_MJ_CREATE:
    DbgPrint('IRP_MJ_CREATE', []);
  IRP_MJ_READ:
    begin
      DbgPrint('IRP_MJ_READ', []);
      len:= strlen(@szBuf[0])+1;
      memcpy(MmGetSystemAddressForMdlSafe(pIrp^.MdlAddress, LowPagePriority), @szBuf[0], len);  
    end;
  IRP_MJ_WRITE:
    begin
      DbgPrint('IRP_MJ_WRITE', []);
      len:= MmGetMdlByteCount(pIrp^.MdlAddress);
      memcpy(@szBuf[0], MmGetSystemAddressForMdlSafe(pIrp^.MdlAddress, LowPagePriority), len);
      DbgPrint('Buffer: %s, Length: %d', [szBuf, len]);
    end;
  IRP_MJ_CLOSE:
    DbgPrint('IRP_MJ_CLOSE', []);
  end;
  
  Result:= STATUS_SUCCESS;
  pIrp^.IoStatus.Status:= Result;
  pIrp^.IoStatus.Information:= len;
  IoCompleteRequest(pIrp, IO_NO_INCREMENT);
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
  pOurDevice^.Flags:= pOurDevice^.Flags or DO_DIRECT_IO;
  pOurDevice^.Flags:= pOurDevice^.Flags and not DO_DEVICE_INITIALIZING;
  Result:= IoCreateSymbolicLink(@suSymName, @suDevName);
end;

function _DriverEntry(pOurDriver:PDRIVER_OBJECT; pOurRegistry:PUNICODE_STRING):NTSTATUS; stdcall;
begin
  pOurDriver^.MajorFunction[IRP_MJ_PNP]:= @IrpPnp;
  pOurDriver^.MajorFunction[IRP_MJ_CREATE]:= @IrpFile;
  pOurDriver^.MajorFunction[IRP_MJ_READ]:= @IrpFile;
  pOurDriver^.MajorFunction[IRP_MJ_WRITE]:= @IrpFile;
  pOurDriver^.MajorFunction[IRP_MJ_CLOSE]:= @IrpFile;
  pOurDriver^.DriverExtension^.AddDevice:=@AddDevice;
  pOurDriver^.DriverUnload:=@Unload;
  Result:=STATUS_SUCCESS;
end;
end.
