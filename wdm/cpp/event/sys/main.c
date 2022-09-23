#include <wdm.h>

#define DEV_NAME L"\\Device\\MyDriver"
#define SYM_NAME L"\\DosDevices\\MyDriver"

#define MAX_THREAD 3

KEVENT myEvent={0};
PVOID pThread[MAX_THREAD]={0};
PDEVICE_OBJECT pNextDevice=NULL;

void MyThread(PVOID pParam)
{
  int t=(int)pParam;
  NTSTATUS status=0;
  LARGE_INTEGER stTime;
 
  switch(t){
  case 0:
    stTime.HighPart|= -1;
    stTime.LowPart = -10000000;
    DbgPrint("Thread%d, Sleeping", t);
    KeDelayExecutionThread(KernelMode, FALSE, &stTime);
    DbgPrint("Thread%d, SetEvent", t);
    KeSetEvent(&myEvent, IO_NO_INCREMENT, FALSE);
    break;
  default:
    DbgPrint("Thread%d, Waiting", t);
    status = KeWaitForSingleObject(&myEvent, Executive, KernelMode, FALSE, NULL);
    DbgPrint("Thread%d, Complete", t);
    break;
  }
  PsTerminateSystemThread(STATUS_SUCCESS);
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
  return STATUS_SUCCESS;
}

void Unload(PDRIVER_OBJECT pOurDriver)
{
  pOurDriver = pOurDriver;
}

NTSTATUS IrpPnp(PDEVICE_OBJECT pOurDevice, PIRP pIrp)
{
  int cc=0;
  UNICODE_STRING usSymboName={0};
  PIO_STACK_LOCATION psk = IoGetCurrentIrpStackLocation(pIrp);

  if(psk->MinorFunction == IRP_MN_REMOVE_DEVICE){
    for(cc=0; cc<MAX_THREAD; cc++){
      if(pThread[cc] != NULL){
        KeWaitForSingleObject(pThread[cc], Executive, KernelMode, FALSE, NULL);
        ObDereferenceObject(pThread[cc]);
      }
    }
    RtlInitUnicodeString(&usSymboName, SYM_NAME);
    IoDeleteSymbolicLink(&usSymboName);
    IoDetachDevice(pNextDevice);
    IoDeleteDevice(pOurDevice);
  }
  IoSkipCurrentIrpStackLocation(pIrp);
  return IoCallDriver(pNextDevice, pIrp);
}

NTSTATUS DriverEntry(PDRIVER_OBJECT pOurDriver, PUNICODE_STRING pOurRegistry)
{
  int cc=0;
  HANDLE hThread=0;
  NTSTATUS status=0;

  pOurDriver->MajorFunction[IRP_MJ_PNP] = IrpPnp;
  pOurDriver->DriverExtension->AddDevice = AddDevice;
  pOurDriver->DriverUnload = Unload;

  KeInitializeEvent(&myEvent, NotificationEvent, FALSE);
  for(cc=0; cc<MAX_THREAD; cc++){
    status = PsCreateSystemThread(&hThread, THREAD_ALL_ACCESS, NULL, (PHANDLE)-1, NULL, MyThread, (PVOID)cc);
    if(status == STATUS_SUCCESS){
      ObReferenceObjectByHandle(hThread, THREAD_ALL_ACCESS, NULL, KernelMode, &pThread[cc], NULL);
      ZwClose(hThread);
    }
  }
  return STATUS_SUCCESS;
}
