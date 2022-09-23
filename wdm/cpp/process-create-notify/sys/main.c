#include <ntddk.h>
#include <ntstrsafe.h>
  
PDEVICE_OBJECT pNextDevice=NULL;
 
void Handler(HANDLE ParentId, HANDLE ProcessId, BOOLEAN Create)
{
  DbgPrint("ppid:0x%x, pid:0x%x, creation:%d", ParentId, ProcessId, Create);
}
 
NTSTATUS AddDevice(PDRIVER_OBJECT pOurDriver, PDEVICE_OBJECT pPhyDevice)
{
  PDEVICE_OBJECT pOurDevice=NULL;
  UNICODE_STRING usDeviceName;
  
  RtlInitUnicodeString(&usDeviceName, L"\\Device\\MyDriver");
  IoCreateDevice(pOurDriver, 0, &usDeviceName, FILE_DEVICE_UNKNOWN, 0, FALSE, &pOurDevice);
  pNextDevice = IoAttachDeviceToDeviceStack(pOurDevice, pPhyDevice);
  pOurDevice->Flags&= ~DO_DEVICE_INITIALIZING;
  pOurDevice->Flags|= DO_BUFFERED_IO;
  return STATUS_SUCCESS;
}
  
void Unload(PDRIVER_OBJECT pOurDriver)
{
}
  
NTSTATUS IrpDispatch(PDEVICE_OBJECT pOurDevice, PIRP pIrp)
{
  PIO_STACK_LOCATION psk = IoGetCurrentIrpStackLocation(pIrp);
  
  if(psk->MinorFunction == IRP_MN_REMOVE_DEVICE){
    PsSetCreateProcessNotifyRoutine(Handler, TRUE);
    IoDetachDevice(pNextDevice);
    IoDeleteDevice(pOurDevice);
  }
  IoSkipCurrentIrpStackLocation(pIrp);
  return IoCallDriver(pNextDevice, pIrp);
}
  
NTSTATUS DriverEntry(PDRIVER_OBJECT pOurDriver, PUNICODE_STRING pOurRegistry)
{
  PsSetCreateProcessNotifyRoutine(Handler, FALSE);
  pOurDriver->MajorFunction[IRP_MJ_PNP] = IrpDispatch;
  pOurDriver->DriverExtension->AddDevice = AddDevice;
  pOurDriver->DriverUnload = Unload;
  return STATUS_SUCCESS;
}
