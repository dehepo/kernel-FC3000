.386p
.model flat, stdcall
option casemap:none
 
include c:\masm32\include\w2k\hal.inc
include c:\masm32\include\w2k\ntstatus.inc
include c:\masm32\include\w2k\ntddk.inc
include c:\masm32\include\w2k\ntoskrnl.inc
include c:\masm32\include\w2k\ntddkbd.inc
include c:\masm32\Macros\Strings.mac
includelib c:\masm32\lib\wxp\i386\hal.lib
includelib c:\masm32\lib\wxp\i386\ntoskrnl.lib

public DriverEntry

MAX_THREAD equ 3

.data
myEvent KEVENT <>
pNextDev PDEVICE_OBJECT 0

.const
DEV_NAME word "\","D","e","v","i","c","e","\","M","y","D","r","i","v","e","r",0
SYM_NAME word "\","D","o","s","D","e","v","i","c","e","s","\","M","y","D","r","i","v","e","r",0

MSG_SLEEPING byte "Thread%d, Sleeping",0
MSG_SETEVENT byte "Thread%d, SetEvent",0
MSG_WAITING  byte "Thread%d, Waiting",0
MSG_COMPLETE byte "Thread%d, Complete",0

.code
MyThread proc pParam:DWORD
  local stTime:LARGE_INTEGER
  
  mov eax, pParam
  .if eax == 0
    or stTime.HighPart, -1
    mov stTime.LowPart, -10000000
    invoke DbgPrint, offset MSG_SLEEPING, pParam
    invoke KeDelayExecutionThread, KernelMode, FALSE, addr stTime
    invoke DbgPrint, offset MSG_SETEVENT, pParam
    invoke KeSetEvent, offset myEvent, IO_NO_INCREMENT, FALSE
  .else
    invoke DbgPrint, offset MSG_WAITING, pParam
    invoke KeWaitForSingleObject, offset myEvent, Executive, KernelMode, FALSE, NULL
    invoke DbgPrint, offset MSG_COMPLETE, pParam
  .endif
  invoke PsTerminateSystemThread, STATUS_SUCCESS
  ret
MyThread endp

IrpPnp proc pDevObj:PDEVICE_OBJECT, pIrp:PIRP
  local pdx:PTR OurDeviceExtension
  local szSymName:UNICODE_STRING

  mov eax, pDevObj
  push (DEVICE_OBJECT PTR [eax]).DeviceExtension
  pop pdx
   
  IoGetCurrentIrpStackLocation pIrp
  movzx eax, (IO_STACK_LOCATION PTR [eax]).MinorFunction
  .if eax == IRP_MN_START_DEVICE
    mov eax, pIrp
    mov (_IRP PTR [eax]).IoStatus.Status, STATUS_SUCCESS
  .elseif eax == IRP_MN_REMOVE_DEVICE
    invoke RtlInitUnicodeString, addr szSymName, offset SYM_NAME
    invoke IoDeleteSymbolicLink, addr szSymName     
    mov eax, pIrp
    mov (_IRP PTR [eax]).IoStatus.Status, STATUS_SUCCESS

    mov eax, pdx
    invoke IoDetachDevice, pNextDev
    invoke IoDeleteDevice, pDevObj
  .endif
  IoSkipCurrentIrpStackLocation pIrp

  mov eax, pdx
  invoke IoCallDriver, pNextDev, pIrp
  ret
IrpPnp endp

AddDevice proc pOurDriver:PDRIVER_OBJECT, pPhyDevice:PDEVICE_OBJECT
  local pOurDevice:PDEVICE_OBJECT
  local suDevName:UNICODE_STRING
  local szSymName:UNICODE_STRING

  invoke RtlInitUnicodeString, addr suDevName, offset DEV_NAME
  invoke RtlInitUnicodeString, addr szSymName, offset SYM_NAME
  invoke IoCreateDevice, pOurDriver, 0, addr suDevName, FILE_DEVICE_UNKNOWN, 0, FALSE, addr pOurDevice
  .if eax == STATUS_SUCCESS
    invoke IoAttachDeviceToDeviceStack, pOurDevice, pPhyDevice
    .if eax != NULL
      push eax
      pop pNextDev

      mov eax, pOurDevice
      or (DEVICE_OBJECT PTR [eax]).Flags, DO_BUFFERED_IO
      and (DEVICE_OBJECT PTR [eax]).Flags, not DO_DEVICE_INITIALIZING
      invoke IoCreateSymbolicLink, addr szSymName, addr suDevName
    .endif
  .endif
  ret
AddDevice endp

Unload proc pOurDriver:PDRIVER_OBJECT
  ret
Unload endp

DriverEntry proc pOurDriver:PDRIVER_OBJECT, pOurRegistry:PUNICODE_STRING
  local hThread:DWORD
  local cnt:DWORD

  mov eax, pOurDriver
  mov (DRIVER_OBJECT PTR [eax]).MajorFunction[IRP_MJ_PNP    * (sizeof PVOID)], offset IrpPnp
  mov (DRIVER_OBJECT PTR [eax]).DriverUnload, offset Unload
  mov eax, (DRIVER_OBJECT PTR [eax]).DriverExtension
  mov (DRIVER_EXTENSION PTR [eax]).AddDevice, AddDevice

  invoke KeInitializeEvent, offset myEvent, NotificationEvent, FALSE
  mov cnt, 0
th:
  invoke PsCreateSystemThread, addr hThread, THREAD_ALL_ACCESS, NULL, -1, NULL, offset MyThread, cnt
  .if eax == STATUS_SUCCESS
    invoke ZwClose, hThread
  .endif
  inc cnt
  cmp cnt, MAX_THREAD
  jnz th
  mov eax, STATUS_SUCCESS
  ret
DriverEntry endp
end DriverEntry
.end
