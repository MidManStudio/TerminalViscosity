// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "heat_distort.fs"
// ============================================================================

#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform float time;
uniform float strength;

out vec4 finalColor;

// Screen-space ripple that stands in for the heat-wave effect. Reads the whole
// scene as a texture, so it can later be limited to a radius around a blast.
// The scene is opaque, so its alpha is forced to 1. Blending a translucent
// object into the scene texture leaves less than 1 in the alpha channel, which
// would show the black behind it.
void main()
{
    vec2 uv = fragTexCoord;
    vec2 wobble = vec2(
        sin(uv.y * 40.0 + time * 6.0),
        cos(uv.x * 40.0 + time * 5.0)
    ) * 0.0015 * strength;
    vec3 scene = texture(texture0, uv + wobble).rgb;
    finalColor = vec4(scene, 1.0) * colDiffuse * fragColor;
}
