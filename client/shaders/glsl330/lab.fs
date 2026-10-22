// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "lab.fs"
// ============================================================================

#version 330

in vec3 fragPos;
in vec3 fragNormal;
in vec4 fragColor;
in vec2 fragMaterial;

uniform vec3 eyePos;

out vec4 finalColor;

const vec3 fogColor = vec3(0.80, 0.84, 0.88);

// The lab has no real lights. Shading is a sky-and-floor ambient term, a soft
// key light from above, full brightness for the ceiling panels and counter
// glow, a sheen on glossy surfaces that grows at a slant, and fog that fades
// the far end of the room.
void main()
{
    vec3 n = normalize(fragNormal);
    vec3 v = normalize(eyePos - fragPos);
    float sky = n.y * 0.5 + 0.5;
    vec3 ambient = mix(vec3(0.34, 0.37, 0.42), vec3(0.78, 0.82, 0.88), sky);
    float key = max(dot(n, normalize(vec3(0.25, 1.0, 0.35))), 0.0);

    vec3 base = fragColor.rgb;
    vec3 lit = base * (ambient + 0.30 * key);
    lit = mix(lit, base * 1.15, fragMaterial.x);

    float slant = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);
    lit += fragMaterial.y * (0.10 + 0.55 * slant) * vec3(0.78, 0.86, 0.95);

    float fog = clamp((length(eyePos - fragPos) - 10.0) / 22.0, 0.0, 1.0);
    finalColor = vec4(mix(clamp(lit, 0.0, 1.0), fogColor, fog), 1.0);
}
