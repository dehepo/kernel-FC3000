#include <wdm.h>

#define DEV_NAME L"\\Device\\MyDriver"
#define SYM_NAME L"\\DosDevices\\MyDriver"

#define MAX_THREAD 3

KSPIN_LOCK myLock={0};
PVOID pThread[MAX_THREAD]={0};
PDEVICE_OBJECT pNextDevice=NULL;

void RunMe(int t)
{
  int c0=0, c1=0;
  KIRQL oldirql=0;
  
  DbgPrint("Thread%d, Locking", t);
  KeAcquireSpinLock(&myLock, &oldirql);
  DbgPrint("Thread%d, Locked", t);

  for(c0=0; c0<10000; c0++){
    for(c1=0; c1<10000; c1++){
    }
  }

  DbgPrint("Thread%d, Unlocking", t);
  KeReleaseSpinLock(&myLock, oldirql);
  DbgPrint("Thread%d, Unlocked", t);
}

void MyThread(PVOID pParam)
{
  LARGE_INTEGER stTime;
 
  stTime.HighPart|= -1;
  stTime.LowPart = -10000000;
  KeDelayExecutionThread(KernelMode, FALSE, &stTime);

  RunMe((int)pParam);
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

  KeInitializeSpinLock(&myLock);
  for(cc=0; cc<MAX_THREAD; cc++){
    status = PsCreateSystemThread(&hThread, THREAD_ALL_ACCESS, NULL, (PHANDLE)-1, NULL, MyThread, (PVOID)cc);
    if(status == STATUS_SUCCESS){
      ObReferenceObjectByHandle(hThread, THREAD_ALL_ACCESS, NULL, KernelMode, &pThread[cc], NULL);
      ZwClose(hThread);
    }
  }
  return STATUS_SUCCESS;
}
