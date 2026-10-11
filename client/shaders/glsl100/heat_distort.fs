// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "heat_distort.fs"
// ============================================================================

#version 100

precision mediump float;

varying vec2 fragTexCoord;
varying vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform float time;
uniform float strength;

// GLES 2 version of the glsl330 shader. Keep the two in step by hand.
void main()
{
    vec2 uv = fragTexCoord;
    vec2 wobble = vec2(
        sin(uv.y * 40.0 + time * 6.0),
        cos(uv.x * 40.0 + time * 5.0)
    ) * 0.0015 * strength;
    gl_FragColor = texture2D(texture0, uv + wobble) * colDiffuse * fragColor;
}
