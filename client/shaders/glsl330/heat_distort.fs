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
void main()
{
    vec2 uv = fragTexCoord;
    vec2 wobble = vec2(
        sin(uv.y * 40.0 + time * 6.0),
        cos(uv.x * 40.0 + time * 5.0)
    ) * 0.0015 * strength;
    finalColor = texture(texture0, uv + wobble) * colDiffuse * fragColor;
}
