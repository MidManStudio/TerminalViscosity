// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "balloon.fs"
// ============================================================================

#version 100

#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec3 fragPos;
varying vec3 fragNormal;
varying float fragKnot;
varying vec3 fragDir;

uniform vec3 eyePos;
uniform vec3 lightDir;
uniform vec3 tint;
uniform float backFace;
uniform float strain; // 0 for a slack balloon, 1 at the point where it bursts
uniform sampler2D texture0; // the drawing, 256 by 256
uniform float artOn; // 1 when the balloon has a drawing
uniform float artTurn; // how far round the balloon the drawing is turned, as a share of a turn

// GLES 2 version of the glsl330 shader. Keep the two in step by hand.
void main()
{
    vec3 n = normalize(fragNormal);
    if (backFace > 0.5) n = -n;
    vec3 v = normalize(eyePos - fragPos);
    float facing = clamp(dot(n, v), 0.0, 1.0);
    float rim = pow(1.0 - facing, 3.0);

    float diffuse = clamp(dot(n, lightDir) * 0.5 + 0.5, 0.0, 1.0);
    vec3 h = normalize(lightDir + v);
    float spec = pow(clamp(dot(n, h), 0.0, 1.0), 28.0);

    vec3 r = reflect(-v, n);
    float sky = smoothstep(-0.3, 0.7, r.y);
    vec3 env = mix(vec3(0.10, 0.12, 0.17), vec3(0.65, 0.78, 0.95), sky);

    vec3 liquid = tint * (0.30 + 0.70 * diffuse);
    vec3 color = liquid + env * (0.10 + 0.55 * rim) + vec3(spec * 0.42);
    float alpha = mix(0.55, 0.95, rim);

    vec3 rubber = tint * 0.7 * (0.35 + 0.65 * diffuse) + env * 0.10 + vec3(spec * 0.3);
    color = mix(color, rubber, fragKnot);
    alpha = mix(alpha, 1.0, fragKnot);


    // The drawing: the picture goes once round the balloon and once from the tip to the
    // bottom, taken from where the vertex was at rest, so it stays on the rubber as it
    // stretches. Bare rubber has no paint, and paint is opaque.
    if (artOn > 0.5 && dot(fragDir, fragDir) > 0.5) {
        vec3 d = normalize(fragDir);
        float u = atan(d.z, d.x + 0.000001) * 0.15915494 + 0.5 + artTurn;
        float vv = acos(clamp(d.y, -1.0, 1.0)) * 0.31830989;
        vec4 paint = texture2D(texture0, vec2(u, vv));
        vec3 painted = paint.rgb * (0.40 + 0.60 * diffuse) + vec3(spec * 0.22);
        float p = paint.a * (1.0 - fragKnot);
        color = mix(color, painted, p);
        alpha = mix(alpha, 1.0, p);
    }

    // Stretched rubber goes thin and pale, so a balloon near its limit looks it.
    float thin = strain * (1.0 - fragKnot);
    alpha *= 1.0 - 0.45 * thin;
    color += vec3(0.28) * thin * (0.5 + rim);

    if (backFace > 0.5) {
        color *= 0.55;
        alpha *= 0.8;
    }
    gl_FragColor = vec4(color, alpha);
}
