unit main;

interface
  uses
    DDDK;
    
  const
    DEV_NAME = '\Device\MyDriver';
    SYM_NAME = '\DosDevices\MyDriver';
    IOCTL_QUEUE = (FILE_DEVICE_UNKNOWN shl 16) or (FILE_ANY_ACCESS shl 14) or ($800 shl 2) or (METHOD_BUFFERED);
    IOCTL_PROCESS = (FILE_DEVICE_UNKNOWN shl 16) or (FILE_ANY_ACCESS shl 14) or ($801 shl 2) or (METHOD_BUFFERED);

  function _DriverEntry(pOurDriver:PDRIVER_OBJECT; pOurRegistry:PUNICODE_STRING):NTSTATUS; stdcall;

implementation
var
  dpc: TKDpc;
  obj: KTIMER;
  csq: IO_CSQ;
  lock: KSPIN_LOCK;
  queue: LIST_ENTRY;
  pNextDevice: PDEVICE_OBJECT;

procedure CsqInsertIrp(pCsqInfo:PIO_CSQ; pIrp:PIRP); stdcall;
begin
  DbgPrint('CsqInsertIrp', []);
  InsertTailList(@queue, @pIrp^.Tail.Overlay.s1.ListEntry);
end;
 
procedure CsqRemoveIrp(pCsqInfo:PIO_CSQ; pIrp:PIRP); stdcall;
begin
  DbgPrint('CsqRemoveIrp', []);
  RemoveEntryList(@pIrp^.Tail.Overlay.s1.ListEntry);
end;
 
function CsqPeekNextIrp(Csq:PIO_CSQ; Irp:PIRP; PeekContext:Pointer):PIRP; stdcall;
begin
  DbgPrint('CsqPeekNextIrp', []);
  Result:= Nil;
end;
 
procedure CsqAcquireLock(Csq:PIO_CSQ; Irql:PKIRQL); stdcall;
begin
  DbgPrint('CsqAcquireLock', []);
  KiAcquireSpinLock(@lock);
end;
 
procedure CsqReleaseLock(Csq:PIO_CSQ; Irql:KIRQL); stdcall;
begin
  if Irql = DISPATCH_LEVEL then
  begin
    KefReleaseSpinLockFromDpcLevel(@lock);
    DbgPrint('CsqReleaseLock at DPC level', []);
  end else
  begin
    KiReleaseSpinLock(@lock);
    DbgPrint('CsqReleaseLock at Passive level', []);
  end;
end;
 
procedure CsqCompleteCanceledIrp(Csq:PIO_CSQ; pIrp:PIRP); stdcall;
begin
  DbgPrint('CsqCompleteCanceledIrp', []);
  pIrp^.IoStatus.Status:= STATUS_CANCELLED;
  pIrp^.IoStatus.Information:= 0;
  IoCompleteRequest(pIrp, IO_NO_INCREMENT);
end;

procedure OnTimer(Dpc:KDPC; DeferredContext:Pointer; SystemArgument1:Pointer; SystemArgument2:Pointer); stdcall;
var
  irp: PIRP;
  plist: PLIST_ENTRY;
   
begin
  if IsListEmpty(@queue) = True then
  begin
    KeCancelTimer(@obj);
    DbgPrint('Finish', []);
  end
  else
  begin
    plist:= RemoveHeadList(@queue);
     
    // CONTAINING_RECORD(IRP.Tail.Overlay.ListEntry)
    irp:= Pointer(Integer(plist) - 88);
    if irp^.Cancel = False then
    begin
      irp^.IoStatus.Status:= STATUS_SUCCESS;
      irp^.IoStatus.Information:= 0;
      IoCompleteRequest(irp, IO_NO_INCREMENT);
      DbgPrint('Complete Irp', []);
    end
    else
    begin
      irp^.CancelRoutine:= Nil;
      irp^.IoStatus.Status:= STATUS_CANCELLED;
      irp^.IoStatus.Information:= 0;
      IoCompleteRequest(irp, IO_NO_INCREMENT);
      DbgPrint('Cancel Irp', []);
    end;
  end;
end;

procedure Unload(pOurDriver:PDRIVER_OBJECT); stdcall;
begin
end;

function IrpFile(pOurDevice:PDEVICE_OBJECT; pIrp:PIRP):NTSTATUS; stdcall;
var
  psk: PIO_STACK_LOCATION;
  
begin
  psk:= IoGetCurrentIrpStackLocation(pIrp);
  case psk^.MajorFunction of
  IRP_MJ_CREATE:
    DbgPrint('IRP_MJ_CREATE', []);
  IRP_MJ_CLOSE:
    DbgPrint('IRP_MJ_CLOSE', []);
  end;
  
  Result:= STATUS_SUCCESS;
  pIrp^.IoStatus.Status:= Result;
  pIrp^.IoStatus.Information:= 0;
  IoCompleteRequest(pIrp, IO_NO_INCREMENT);
end;

function IrpIOCTL(pOurDevice:PDeviceObject; pIrp:PIrp):NTSTATUS; stdcall;
var
  code: ULONG;
  tt: LARGE_INTEGER;
  psk: PIO_STACK_LOCATION;
   
begin
  psk:= IoGetCurrentIrpStackLocation(pIrp);
  code:= psk^.Parameters.DeviceIoControl.IoControlCode;
  case code of
  IOCTL_QUEUE:
    begin
      DbgPrint('IOCTL_QUEUE', []);
      IoCsqInsertIrp(@csq, pIrp, Nil);
      Result:= STATUS_PENDING;
      exit
    end;
  IOCTL_PROCESS:
    begin
      DbgPrint('IOCTL_PROCESS', []);
      tt.HighPart:= tt.HighPart or -1;
      tt.LowPart:= ULONG(-10000000);
      KeSetTimerEx(@obj, tt.LowPart, tt.HighPart, 1000, @dpc);
    end;
  end;
   
  Result:= STATUS_SUCCESS;
  pIrp^.IoStatus.Information:= 0;
  pIrp^.IoStatus.Status:= Result;
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
  pOurDevice^.Flags:= pOurDevice^.Flags or DO_BUFFERED_IO;
  pOurDevice^.Flags:= pOurDevice^.Flags and not DO_DEVICE_INITIALIZING;
  InitializeListHead(@queue);
  KeInitializeSpinLock(@lock);
  KeInitializeTimer(@obj);
  KeInitializeDpc(@dpc, OnTimer, pOurDevice);
  IoCsqInitialize(@csq, CsqInsertIrp, CsqRemoveIrp, CsqPeekNextIrp, CsqAcquireLock, CsqReleaseLock, CsqCompleteCanceledIrp);
  Result:= IoCreateSymbolicLink(@suSymName, @suDevName);
end;

function _DriverEntry(pOurDriver:PDRIVER_OBJECT; pOurRegistry:PUNICODE_STRING):NTSTATUS; stdcall;
begin
  pOurDriver^.MajorFunction[IRP_MJ_PNP]:= @IrpPnp;
  pOurDriver^.MajorFunction[IRP_MJ_CREATE]:= @IrpFile;
  pOurDriver^.MajorFunction[IRP_MJ_CLOSE]:= @IrpFile;
  pOurDriver^.MajorFunction[IRP_MJ_DEVICE_CONTROL] := @IrpIOCTL;
  pOurDriver^.DriverExtension^.AddDevice:=@AddDevice;
  pOurDriver^.DriverUnload:=@Unload;
  Result:=STATUS_SUCCESS;
end;
end.
