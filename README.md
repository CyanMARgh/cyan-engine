**requirements**
- OS: Linux / Windows (but with less features now)
- compiler version: beta 0.1.088
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
To build and run all demos in order, set `BUILD_ALL :: true;` and `RUN :: true;` inside first.jai. You can comapre results with photos from expected_result folder

Most of demos has the ability to rotate the camera: wasd,space,shift - move, qerf/mouse - rotate.
Turn on/off camera movement - LMB.

demos list:
- 0: hello triangle
- 1: gltf model loading (normals as color)
- 2: single texture load & show
- 3: instanced drawing for primitives
- 4, 5: particles (trough Atoms_Painter and distinct particle system). Particles appear when you hold down LMB.
- 6: g-buffer
- 7: same as 3, but with right depth order
- 8: font loading
- 9: SSAO
- 10-12: PBR (different variants)
- 13: semitransparent surfaces (weighted, blended)
- 14: edge detection
- 15: characters painting
- 16: UI example
- 17: SDF-based render mixed with traditional g-buffer pipeline (depth testing works well while camera outside of fractal's bounding box)
- 18: gltf's animations (only movement & rotation)
- 19: shell-rendered moss ball
- 20: simple floor "reflection"
- 21: massive light rendering (you can turn on `SHOW_ZONES :: true;` to see bounding boxes of sources)
- 22: PBAO (prebaked ambient occlusion), step 1: slice of 3d model
- 23: raymarching minimum demo
- 24: PBAO, step 2: voxelization (ATTENTION: VERY LAGGY, this voxels are only for debugging purposes)
- 25: PBAO, step 3: generating slice of occlusion volume