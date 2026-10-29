#version 450

#include "common.inc"

#define BLUR_AXIS vec2(1.0, 0.0)
#define BLUR_SPREAD 1.5
#include "blur.inc"
