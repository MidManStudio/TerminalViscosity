// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "vessel.fs"
// ============================================================================

#version 330

in vec3 fragPos;
in vec3 fragNormal;
in vec4 fragColor;
in vec2 fragMaterial;

uniform vec3 eyePos;
uniform float liquidMode; // 0 draws the glass, 1 draws the liquid inside it
uniform float levelY;     // height of the liquid surface in the world
uniform vec3 liquidColor;

out vec4 finalColor;

const vec3 fogColor = vec3(0.80, 0.84, 0.88);
const vec3 lightDir = vec3(0.2191, 0.8765, 0.4303); // the room's key light, normalized

// Glass is almost clear in the middle of a surface and turns solid toward its
// edge, with a bright glint where it catches the light. Liquid is cut off at a
// flat surface in world space. The liquid is drawn as a closed solid, so where
// it is cut we see the inside of its far wall, and that is painted as the
// surface.
void main()
{
    vec3 n = normalize(fragNormal);
    vec3 v = normalize(eyePos - fragPos);
    float fog = clamp((length(eyePos - fragPos) - 10.0) / 22.0, 0.0, 1.0);

    if (liquidMode > 0.5) {
        if (fragPos.y > levelY) {
            discard;
        }
        vec3 normal = gl_FrontFacing ? n : vec3(0.0, 1.0, 0.0);
        float sky = normal.y * 0.5 + 0.5;
        vec3 ambient = mix(vec3(0.34, 0.37, 0.42), vec3(0.78, 0.82, 0.88), sky);
        float key = max(dot(normal, lightDir), 0.0);
        vec3 lit = liquidColor * (ambient + 0.30 * key);
        if (gl_FrontFacing) {
            lit *= 0.82;
        } else {
            lit += 0.30 * pow(max(dot(reflect(-lightDir, normal), v), 0.0), 24.0);
        }
        finalColor = vec4(mix(clamp(lit, 0.0, 1.0), fogColor, fog), 1.0);
        return;
    }

    float facing = clamp(abs(dot(n, v)), 0.0, 1.0);
    float rim = pow(1.0 - facing, 3.0);
    float glint = pow(max(dot(reflect(-lightDir, n), v), 0.0), 40.0);
    float sky = n.y * 0.5 + 0.5;
    vec3 body = fragColor.rgb * mix(0.75, 1.1, sky);
    vec3 lit = body + vec3(0.85, 0.92, 1.0) * (0.35 * rim + 0.9 * glint);
    float alpha = clamp(0.16 + 0.55 * rim + 0.8 * glint, 0.0, 0.88);
    finalColor = vec4(mix(clamp(lit, 0.0, 1.0), fogColor, fog), alpha);
}
