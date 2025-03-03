# Fluorescence

<img src="https://github.com/nithinp7/Fluorescence/blob/main/Screenshots/SDF.png" width=800px/>

Fluorescence is an application for fast prototyping and development of GPU-driven projects like rendering technique studies, GPU driven simulations, and procedural art. It is inspired by the ease-of-use of shadertoy, while retaining a bit more expressiveness for more complicated projects. It uses a custom text-based project format (".flr") which allows declarations of structures, buffers, and shaders, along with the sequence of GPU tasks (dispatches, draws, transitions, etc) performed each frame. UI inputs can be declared and transparently referenced in shader code. Texture files can be loaded / saved and a simple OBJ loader is built into the application. 

The application is built on top of my rendering engine, [Althea](https://github.com/nithinp7/Althea).

## Projects

### Skin Rendering

WIP implementation of screen-space subsurface scattering

<img src="https://github.com/nithinp7/Fluorescence/blob/main/Screenshots/IBL_Skin_2.png"/>
<img src="https://github.com/nithinp7/Fluorescence/blob/main/Screenshots/IBL_Skin_0.png"/>
<img src="https://github.com/nithinp7/Fluorescence/blob/main/Screenshots/ScreenSpaceSSS.png"/>

### Diffusion Profile Generator

<p float="left">
<img src="https://github.com/nithinp7/Fluorescence/blob/main/Projects/Skin/DiffusionProfile.png" height=400px/>
<img src="https://github.com/nithinp7/Fluorescence/blob/main/Screenshots/DiffusionSpectrum.png" height=400px/>
</p>

### Stable Fluids - 3D Implementation + Raymarched Lighting


<img src="https://github.com/nithinp7/Fluorescence/blob/main/Screenshots/Smoke3D.jpg" height=400px/>
<img src="https://github.com/nithinp7/Fluorescence/blob/main/Screenshots/Smoke3D_2.png" height=400px/>


### Stable Fluids - 2D Implementation

<img src="https://github.com/nithinp7/Fluorescence/blob/main/Screenshots/StableFluids2D.gif" width=800px/>

### Atmospheric Scattering

<img src="https://github.com/nithinp7/Fluorescence/blob/main/Screenshots/SunSky2.png" width=800px/>
<img src="https://github.com/nithinp7/Fluorescence/blob/main/Screenshots/SunSky3.png" width=800px/>

### SDF Pathtracer


### Smoothed Particle Hydrodynamics (SPH) - 2D Implementation

<img src="https://github.com/nithinp7/Fluorescence/blob/main/Screenshots/SPH.gif"/>

More demo projects, screenshots, and proper documentation for the ".flr" format to come.
