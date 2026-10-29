#version 450

#include "common.inc"

#define BLUR_AXIS vec2(0.0, 1.0)
#define BLUR_SPREAD 1.5
#include "blur.inc"
