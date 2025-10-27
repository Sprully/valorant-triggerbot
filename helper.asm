.386                  ; Use 32-bit instructions
.model flat, stdcall  ; Use flat memory and stdcall calling convention (used for Windows API calling)
.stack 4096           ; Set up a stack with a size of 4096 bytes (4 KB)

include win.inc
include helper.inc

includelib user32.lib
includelib kernel32.lib
includelib gdi32.lib
includelib shlwapi.lib

.data
    ; == Structure initializations ==
    bmp_file_header BITMAPFILEHEADER <>
    bmp_info_header BITMAPINFOHEADER <> 
    bmp BITMAP <>
    PUBLIC cfg
    cfg CONFIG <>
    frequency   LARGE_INTEGER <>
    start       LARGE_INTEGER <>
    end_        LARGE_INTEGER <>

    ; == Config related variables ==
    cfg_path         db "config.txt",0
    full_cfg_path    db  MAX_PATH dup(0)
    ini_section1     db "Settings", 0
    ini_name1        db "hold_key", 0 
    ini_name2        db "tap_time", 0 
    ini_name3        db "scan_area", 0
    ini_section2     db "ColorRGB", 0
    ini_name4        db "color_sens", 0
    ini_name5        db "red", 0
    ini_name6        db "green", 0 
    ini_name7        db "blue", 0

    ; == Screenshot related variables ==
    screen_dc        dd 0
    screen_width     dd 0 
    screen_height    dd 0 
    crop_x           dd 0
    crop_y           dd 0
    mem_dc           dd 0
    cbmp             dd 0
    pixels           dd 0
    hFile            dd 0
    filename         db "screenshot.bmp", 0
    bytes_written    dd 0
    status           dd 0

    ; == Color detection related variables ==
    red_val          dd 0
    green_val        dd 0
    blue_val         dd 0
    current_pixels   dd 0

.code
GetScreenshot proc crop_width:DWORD, crop_height:DWORD, save_bmp_file:DWORD 
    invoke GetDC, 0
    cmp eax, 0
    je FAILED
    mov screen_dc, eax

    invoke GetDeviceCaps, screen_dc, DESKTOPHORZRES
    mov screen_width, eax

    invoke GetDeviceCaps, screen_dc, DESKTOPVERTRES
    mov screen_height, eax

    ; Calculate coordinates for center crop
    mov eax, screen_width
    sub eax, crop_width
    mov ebx, 2               
    mov edx, 0
    div ebx          
    mov crop_x, eax 

    mov eax, screen_height
    sub eax, crop_height
    mov ebx, 2         
    mov edx, 0
    div ebx              
    mov crop_y, eax 

    invoke CreateCompatibleDC, screen_dc
    cmp eax, 0
    je FAILED
    mov mem_dc, eax

    invoke CreateCompatibleBitmap, screen_dc, crop_width, crop_height  
    cmp eax, 0
    je FAILED
    mov cbmp, eax 

    invoke SelectObject, mem_dc, cbmp 
    cmp eax, 0
    je FAILED

    invoke BitBlt, mem_dc, 0, 0, crop_width, crop_height, screen_dc, crop_x, crop_y, SRCCOPY
    cmp eax, 0
    je FAILED

    invoke GetObjectA, cbmp, sizeof BITMAP, offset bmp 
    cmp eax, 0
    je FAILED

    ; Create bitmap file header
    mov word ptr [bmp_file_header.bfType], 4D42h ; BM
    mov eax, bmp.bmWidthBytes
    mov ebx, crop_height 
    mul ebx              
    mov ebx, sizeof BITMAPFILEHEADER
    add ebx, sizeof BITMAPINFOHEADER 
    add eax, ebx
    mov bmp_file_header.bfSize, eax
    mov eax, sizeof BITMAPFILEHEADER
    add eax, sizeof BITMAPINFOHEADER 
    mov bmp_file_header.bfOffBits, eax

    ; Create bitmap info header
    invoke RtlFillMemory, offset bmp_info_header, sizeof BITMAPINFOHEADER, 0
    mov bmp_info_header.biSize, sizeof BITMAPINFOHEADER
    mov eax, bmp.bmWidth 
    mov bmp_info_header.biWidth, eax
    mov eax, bmp.bmHeight
    mov bmp_info_header.biHeight, eax
    mov bmp_info_header.biPlanes, 1
    mov bmp_info_header.biBitCount, 32         ; Use 32-bit color 
    mov bmp_info_header.biCompression, BI_RGB  
    mov eax, bmp.bmWidthBytes 
    mov ebx, bmp.bmHeight               
    mul ebx                                
    mov bmp_info_header.biSizeImage, eax

    ; Allocate buffer for bitmap data 
    mov eax, bmp.bmWidthBytes 
    mov ebx, crop_height
    mul ebx
    invoke GlobalAlloc, 0, eax
    cmp eax, 0
    je FAILED
    mov pixels, eax

    invoke GetDIBits, mem_dc, cbmp, 0, crop_height, pixels, offset bmp_info_header, DIB_RGB_COLORS
    cmp eax, 0
    je FAILED

    ; Save BMP file
    cmp save_bmp_file, 0
    je SUCCESS
    
    invoke CreateFileA, offset filename, GENERIC_WRITE, 0, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0 
    cmp eax, INVALID_HANDLE_VALUE
    je FAILED
    mov hFile, eax

    invoke WriteFile, hFile, offset bmp_file_header, sizeof BITMAPFILEHEADER, offset bytes_written, 0
    cmp eax, 0
    je FAILED
    
    invoke WriteFile, hFile, offset bmp_info_header, sizeof BITMAPINFOHEADER, offset bytes_written, 0
    cmp eax, 0
    je FAILED

    mov eax, bmp.bmWidthBytes
    mov ebx, crop_height
    mul ebx

    invoke WriteFile, hFile, pixels, eax, offset bytes_written, 0
    cmp eax, 0
    je FAILED

    invoke CloseHandle, hFile
    cmp eax, 0
    je FAILED

SUCCESS:
    mov status, 1
    cmp screen_dc, 0
    je DELETE_MEM_DC 
    invoke ReleaseDC, 0, screen_dc

DELETE_MEM_DC:
    cmp mem_dc, 0
    je DELETE_CBMP
    invoke DeleteDC, mem_dc

DELETE_CBMP:
    cmp cbmp, 0
    je EXIT 
    invoke DeleteObject, cbmp

DONE:
    cmp status, 1
    je EXIT 
    mov eax, 0
    ret

EXIT:
    mov eax, pixels
    ret

FAILED:
    cmp screen_dc, 0
    je DELETE_MEM_DC 
    invoke ReleaseDC, 0, screen_dc
    jmp DELETE_MEM_DC
GetScreenshot endp

FindColor proc pPixels:DWORD, PixelCount:DWORD, ColorSens:DWORD, red:DWORD, green:DWORD, blue:DWORD
    mov edi, 0
LoopBeg:
    ; pPixels[edx] 
    mov edx, pPixels
    mov eax, [edx + edi * 4]

    mov current_pixels, eax

    ; Extract red from current_pixels
    shr eax, 16
    and eax, 0FFh
    mov red_val, eax
    
    mov eax, current_pixels
    
    ; Extract green from current_pixels
    shr eax, 8 
    and eax, 0FFh
    mov green_val, eax

    mov eax, current_pixels

    ; Extract blue from current_pixels
    and eax, 0FFh
    mov blue_val, eax


    ; == Color sens logic ==

    ; red_val + ColorSens >= red && red_val - ColorSens <= red
    mov eax, red_val
    add eax, ColorSens
    cmp eax, red
    jl COLOR_NOT_FOUND
    mov eax, red_val
    sub eax, ColorSens
    cmp eax, red
    jg COLOR_NOT_FOUND
    
    ; green_val + ColorSens >= green && green_val - ColorSens <= green
    mov eax, green_val
    add eax, ColorSens
    cmp eax, green
    jl COLOR_NOT_FOUND
    mov eax, green_val
    sub eax, ColorSens
    cmp eax, green
    jg COLOR_NOT_FOUND

    ; blue_val + ColorSens >= blue && blue_val - ColorSens <= blue
    mov eax, blue_val
    add eax, ColorSens
    cmp eax, blue
    jl COLOR_NOT_FOUND
    mov eax, blue_val
    sub eax, ColorSens
    cmp eax, blue
    jg COLOR_NOT_FOUND

    mov eax, 1
    ret

COLOR_NOT_FOUND:
    inc edi
    cmp edi, PixelCount
    jl LoopBeg 

    mov eax, 0
    ret
FindColor endp

LeftClick proc h_window:DWORD
    invoke PostMessageA, h_window, WM_LBUTTONDOWN, MK_LBUTTON, 0 
    cmp eax, 0
    je POST_MSG_FAILED

    invoke PostMessageA, h_window, WM_LBUTTONUP, 0, 0 
    cmp eax, 0
    je POST_MSG_FAILED

    mov eax, 1
    ret

POST_MSG_FAILED:
    mov eax, 0
    ret
LeftClick endp

GetConfig proc
    invoke GetFullPathNameA, offset cfg_path, MAX_PATH, offset full_cfg_path, 0 
    invoke PathFileExistsA, offset full_cfg_path
    cmp eax, 0
    jl CONFIG_ERROR 

    invoke GetPrivateProfileIntA, offset ini_section1, offset ini_name1, -1, offset full_cfg_path
    cmp eax, 0
    jl CONFIG_ERROR 
    mov cfg.hold_key, eax

    invoke GetPrivateProfileIntA, offset ini_section1, offset ini_name2, -1, offset full_cfg_path
    cmp eax, 0
    jl CONFIG_ERROR 
    mov cfg.tap_time, eax

    invoke GetPrivateProfileIntA, offset ini_section1, offset ini_name3, -1, offset full_cfg_path
    cmp eax, 0
    jle CONFIG_ERROR 
    mov cfg.scan_area, eax

    invoke GetPrivateProfileIntA, offset ini_section2, offset ini_name4, -1, offset full_cfg_path
    cmp eax, 0
    jl CONFIG_ERROR 
    mov cfg.color_sens, eax

    invoke GetPrivateProfileIntA, offset ini_section2, offset ini_name5, -1, offset full_cfg_path
    cmp eax, 0
    jl CONFIG_ERROR 
    mov cfg.red, eax

    invoke GetPrivateProfileIntA, offset ini_section2, offset ini_name6, -1, offset full_cfg_path
    cmp eax, 0
    jl CONFIG_ERROR 
    mov cfg.green, eax

    invoke GetPrivateProfileIntA, offset ini_section2, offset ini_name7, -1, offset full_cfg_path
    cmp eax, 0
    jl CONFIG_ERROR 
    mov cfg.blue, eax

    mov eax, 1
    ret

CONFIG_ERROR:
    mov eax, 0
    ret
GetConfig endp

PrintConsole proc msg:DWORD
    invoke GetStdHandle, STD_OUTPUT_HANDLE
    mov ebx, eax

    invoke lstrlenA, msg
    mov ecx, eax

    invoke WriteConsoleA, ebx, msg, ecx, 0, 0
    ret
PrintConsole endp

IsKeyPressed proc key:DWORD
    ; 0x8000 is used to check if the key is being pressed down. Use 0x0001 for toggle logic.
    invoke GetAsyncKeyState, key
    and eax, 8000h
    cmp eax, 8000h
    je KEY_PRESSED

    mov eax, 0
    ret

KEY_PRESSED:
    mov eax, 1
    ret
IsKeyPressed endp

InitPerformanceCounters proc
    invoke QueryPerformanceFrequency, offset frequency
    ret
InitPerformanceCounters endp

StartCounter proc
    invoke QueryPerformanceCounter, offset start
    ret
StartCounter endp

StopCounter proc
    invoke  QueryPerformanceCounter, addr end_

    mov     eax, DWORD PTR end_
    mov     edx, DWORD PTR end_+4
    sub     eax, DWORD PTR start
    sbb     edx, DWORD PTR start+4
 
    mov     ebx, 1000
    mul     ebx

    mov     ebx, DWORD PTR frequency
    div     ebx                
    ret
StopCounter endp

end