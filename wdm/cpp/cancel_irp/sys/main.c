#include <wdm.h>

#define IOCTL_QUEUE   CTL_CODE(FILE_DEVICE_UNKNOWN, 0x800, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_PROCESS CTL_CODE(FILE_DEVICE_UNKNOWN, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS)

#define DEV_NAME L"\\Device\\MyDriver"
#define SYM_NAME L"\\DosDevices\\MyDriver"

KDPC stDPC={0};
KTIMER stTime={0};
LIST_ENTRY stQueue={0};
PDEVICE_OBJECT pNextDevice=NULL;

VOID OnTimer(struct _KDPC *Dpc, PVOID DeferredContext, PVOID SystemArgument1, PVOID SystemArgument2)
{
  PIRP pIrp;
  PLIST_ENTRY plist;
  if(IsListEmpty(&stQueue) == TRUE){
    KeCancelTimer(&stTime);
    DbgPrint("Finish");
  }
  else{
    plist = RemoveHeadList(&stQueue);
    pIrp = CONTAINING_RECORD(plist, IRP, Tail.Overlay.ListEntry);
    if(pIrp->Cancel != TRUE){
      pIrp->IoStatus.Status = STATUS_SUCCESS;
      pIrp->IoStatus.Information = 0;
      IoCompleteRequest(pIrp, IO_NO_INCREMENT);
      DbgPrint("Complete Irp");
    }
    else{
      pIrp->CancelRoutine = NULL;
      pIrp->IoStatus.Status = STATUS_CANCELLED;
      pIrp->IoStatus.Information = 0;
      IoCompleteRequest(pIrp, IO_NO_INCREMENT);
      DbgPrint("Cancel Irp");
    }
  }
}

NTSTATUS AddDevice(PDRIVER_OBJECT pOurDriver, PDEVICE_OBJECT pPhyDevice)
{
  PDEVICE_OBJECT pOurDevice=NULL;
  UNICODE_STRING usDeviceName;
  UNICODE_STRING usSymboName;

  RtlInitUnicodeString(&usDeviceName, DEV_NAME);
  IoCreateDevice(pOurDriver, 0, &usDeviceName, FILE_DEVICE_UNKNOWN, 0, FALSE, &pOurDevice);
  RtlInitUnicodeString(&usSymboName, SYM_NAME);
  IoCreateSymbolicLink(&usSymboName, &usDeviceName);
  pNextDevice = IoAttachDeviceToDeviceStack(pOurDevice, pPhyDevice);
  pOurDevice->Flags&= ~DO_DEVICE_INITIALIZING;
  pOurDevice->Flags|= DO_BUFFERED_IO;
  
  InitializeListHead(&stQueue);
  KeInitializeTimer(&stTime);
  KeInitializeDpc(&stDPC, OnTimer, pOurDevice);
  return STATUS_SUCCESS;
}

void Unload(PDRIVER_OBJECT pOurDriver)
{
  pOurDriver = pOurDriver;
}

NTSTATUS IrpPnp(PDEVICE_OBJECT pOurDevice, PIRP pIrp)
{
  PIO_STACK_LOCATION psk = IoGetCurrentIrpStackLocation(pIrp);
  UNICODE_STRING usSymboName;

  if(psk->MinorFunction == IRP_MN_REMOVE_DEVICE){
    RtlInitUnicodeString(&usSymboName, SYM_NAME);
    IoDeleteSymbolicLink(&usSymboName);
    IoDetachDevice(pNextDevice);
    IoDeleteDevice(pOurDevice);
  }
  IoSkipCurrentIrpStackLocation(pIrp);
  return IoCallDriver(pNextDevice, pIrp);
}

NTSTATUS IrpIOCTL(PDEVICE_OBJECT pOurDevice, PIRP pIrp)
{
  LARGE_INTEGER stTimePeriod;
  PIO_STACK_LOCATION psk = IoGetCurrentIrpStackLocation(pIrp);

  switch(psk->Parameters.DeviceIoControl.IoControlCode){
  case IOCTL_QUEUE:
    DbgPrint("IOCTL_QUEUE");
    InsertHeadList(&stQueue, &pIrp->Tail.Overlay.ListEntry);
    IoMarkIrpPending(pIrp);
    return STATUS_PENDING;
  case IOCTL_PROCESS:
    DbgPrint("IOCTL_PROCESS");
    stTimePeriod.HighPart|= -1;
    stTimePeriod.LowPart = -10000000;
    KeSetTimerEx(&stTime, stTimePeriod, 1000, &stDPC);
    break;
  }
  pIrp->IoStatus.Information = 0;
  pIrp->IoStatus.Status = STATUS_SUCCESS;
  IoCompleteRequest(pIrp, IO_NO_INCREMENT);
  return STATUS_SUCCESS;
}

NTSTATUS IrpFile(PDEVICE_OBJECT pOurDevice, PIRP pIrp)
{
  PIO_STACK_LOCATION psk = IoGetCurrentIrpStackLocation(pIrp);

  switch(psk->MajorFunction){
  case IRP_MJ_CREATE:
    DbgPrint("IRP_MJ_CREATE");
    break;
  case IRP_MJ_CLOSE:
    DbgPrint("IRP_MJ_CLOSE");
    break;
  }
  IoCompleteRequest(pIrp, IO_NO_INCREMENT);
  return STATUS_SUCCESS;
}

NTSTATUS DriverEntry(PDRIVER_OBJECT pOurDriver, PUNICODE_STRING pOurRegistry)
{
  pOurDriver->MajorFunction[IRP_MJ_PNP] = IrpPnp;
  pOurDriver->MajorFunction[IRP_MJ_CREATE] =
  pOurDriver->MajorFunction[IRP_MJ_CLOSE] = IrpFile;
  pOurDriver->MajorFunction[IRP_MJ_DEVICE_CONTROL] = IrpIOCTL;
  pOurDriver->DriverExtension->AddDevice = AddDevice;
  pOurDriver->DriverUnload = Unload;
  return STATUS_SUCCESS;
}
