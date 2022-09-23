.386p
.model flat, stdcall
option casemap:none

include c:\masm32\include\w2k\ntstatus.inc
include c:\masm32\include\w2k\ntddk.inc
include c:\masm32\include\w2k\ntoskrnl.inc
include c:\masm32\include\w2k\ntddkbd.inc
include c:\masm32\Macros\Strings.mac
includelib c:\masm32\lib\wxp\i386\ntoskrnl.lib

public DriverEntry

.const
DEV_NAME word "\","D","e","v","i","c","e","\","M","y","D","r","i","v","e","r",0
MSG      byte "Hello, world!",0

.data
pNextDevice PDEVICE_OBJECT 0
 
.code
AddDevice proc pOurDriver:PDRIVER_OBJECT, pPhyDevice:PDEVICE_OBJECT
  local pOurDevice:PDEVICE_OBJECT
  local suDevName:UNICODE_STRING

  invoke DbgPrint, offset MSG
  invoke RtlInitUnicodeString, addr suDevName, offset DEV_NAME
  invoke IoCreateDevice, pOurDriver, 0, addr suDevName, FILE_DEVICE_UNKNOWN, 0, FALSE, addr pOurDevice
  invoke IoAttachDeviceToDeviceStack, pOurDevice, pPhyDevice
  push eax
  pop pNextDevice
  mov eax, pOurDevice
  or (DEVICE_OBJECT PTR [eax]).Flags, DO_BUFFERED_IO
  and (DEVICE_OBJECT PTR [eax]).Flags, not DO_DEVICE_INITIALIZING
  mov eax, STATUS_SUCCESS
  ret
AddDevice endp

Unload proc pOurDriver:PDRIVER_OBJECT
  ret
Unload endp

IrpPnp proc pOurDevice:PDEVICE_OBJECT, pIrp:PIRP
  IoGetCurrentIrpStackLocation pIrp
  movzx eax, (IO_STACK_LOCATION PTR [eax]).MinorFunction
  .if eax == IRP_MN_START_DEVICE
    mov eax, pIrp
    mov (_IRP PTR [eax]).IoStatus.Status, STATUS_SUCCESS
  .elseif eax == IRP_MN_REMOVE_DEVICE  
    mov eax, pIrp
    mov (_IRP PTR [eax]).IoStatus.Status, STATUS_SUCCESS
    invoke IoDetachDevice, pNextDevice
    invoke IoDeleteDevice, pOurDevice
  .endif
  IoSkipCurrentIrpStackLocation pIrp
  invoke IoCallDriver, pNextDevice, pIrp
  ret
IrpPnp endp

DriverEntry proc pOurDriver:PDRIVER_OBJECT, pOurRegistry:PUNICODE_STRING
  mov eax, pOurDriver
  mov (DRIVER_OBJECT PTR [eax]).MajorFunction[IRP_MJ_PNP * (sizeof PVOID)], offset IrpPnp
  mov (DRIVER_OBJECT PTR [eax]).DriverUnload, offset Unload
  mov eax, (DRIVER_OBJECT PTR [eax]).DriverExtension
  mov (DRIVER_EXTENSION PTR [eax]).AddDevice, AddDevice
  mov eax, STATUS_SUCCESS
  ret
DriverEntry endp
end DriverEntry
.end
