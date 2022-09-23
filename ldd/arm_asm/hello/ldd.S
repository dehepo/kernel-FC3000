.global init_module
.global cleanup_module

.section .modinfo, "ae"
__UNIQUE_ID_0: .asciz "license=GPL"
__UNIQUE_ID_1: .asciz "author=Steward Fu"
__UNIQUE_ID_2: .asciz "description=Linux Driver"

.section .text
msg_load:   .asciz "hello, world!\n" 
msg_unload: .asciz "unload it\n"

.align 2
.section .text
init_module:
  push {lr}
  ldr r0, =msg_load
  bl printk
  mov r0, #0
  pop {pc}

cleanup_module:
  push {lr}
  ldr r0, =msg_unload
  bl printk
  pop {pc}
.end
