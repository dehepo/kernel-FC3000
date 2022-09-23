del /s /q main.sys
c:\masm32\bin\ml /c /coff /Cp "main.asm"
c:\masm32\bin\link /MAP /nologo /driver:WDM /base:0x10000 /align:64 /out:"main.sys" /subsystem:native "main.obj"
del /s /q main.map
del /s /q main.obj