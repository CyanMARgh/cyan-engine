**requirements**
- OS: Linux
- compiler version: beta 0.1.073
modules:
- GLTF_Parser module: https://github.com/kooparse/gltf_parser (30 aug, 2023) 
- GLFW module: https://github.com/kujukuju/JaiGLFW (5 jun, 2023)
- Extra_Containers module: https://github.com/CyanMARgh/extra-containers (11 aug 2023)
- (optioanl) ffmpeg installed, for rendering to file

Place them in jai/modules folder or the folder where this module is located. and compie demo with
```
$ cd Cyan_Engine
$ jai first.jai
```
To build and run all demos in order, set `BUILD_AND_RUN_ALL::true;` inside first.jai. You can comapre results with photos from expected_result folder

Most of demos has the ability to rotate the camera: wasd,space,shift - move, qerf/mouse - rotate.
Turn on/off camera movement - LMB.

demos list:
- 0: hello triangle
- 1: gltf model loading (simple color)
- 2: single texture load & show
- 3: instanced drawing for primitives
- 4, 5: particles (trough Atoms_Painter and distinct particle system). Particles appear when you hold down LMB.
- 6: g-buffer
- 7: same as 3, but with right depth order
- 8: font loading
- 9: SSAO
- 11-12: PBR (different variants)
- 13: semitransparent surfaces (weighted, blended)
- 14: edge detection
- 15: characters painting