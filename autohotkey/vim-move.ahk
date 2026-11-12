#Requires AutoHotkey v2.0

; 無変換キー（vk1D）を押している間だけ有効
#HotIf GetKeyState("vk1D", "P")
h::Left
j::Down
k::Up
l::Right
#HotIf
