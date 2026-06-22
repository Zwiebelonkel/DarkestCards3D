shader_type sky;

// --- Basis ---
uniform float time_speed : hint_range(0.0, 5.0) = 0.45;
uniform vec4 zenith_color : source_color = vec4(0.035, 0.0, 0.0, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.85, 0.04, 0.0, 1.0);
uniform vec4 fire_color : source_color = vec4(1.0, 0.22, 0.02, 1.0);
uniform vec4 ash_color : source_color = vec4(0.015, 0.0, 0.0, 1.0);
uniform float sky_rotation_y : hint_range(0.0, 6.28318) = 0.0;

// --- Wolken & Feuer ---
uniform float cloud_scale : hint_range(0.2, 8.0) = 2.8;
uniform float cloud_density : hint_range(0.0, 3.0) = 1.45;
uniform float cloud_speed : hint_range(0.0, 2.0) = 0.18;
uniform float fire_glow_strength : hint_range(0.0, 5.0) = 2.8;
uniform float horizon_fire_height : hint_range(0.0, 1.0) = 0.32;

// --- Portal ---
uniform float portal_size : hint_range(0.01, 0.5) = 0.13;
uniform float portal_glow : hint_range(0.0, 10.0) = 5.5;

// --- Nausea ---
uniform float ash_amount : hint_range(0.0, 2.0) = 0.65;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.22;
uniform float nausea_strength : hint_range(0.0, 1.0) = 0.32;
uniform float nausea_speed : hint_range(0.0, 5.0) = 1.55;
uniform float nausea_waves : hint_range(0.0, 20.0) = 9.0;
uniform float nausea_radial : hint_range(0.0, 1.0) = 0.4;
uniform float nausea_grid : hint_range(0.0, 1.0) = 0.3;

// --- Augen ---
uniform int eye_count : hint_range(1, 8) = 6;
uniform float eye_size : hint_range(0.01, 0.3) = 0.06;
uniform float eye_blink_speed : hint_range(0.0, 5.0) = 1.2;
uniform float eye_gaze_range : hint_range(0.0, 1.0) = 0.5;
uniform float eye_bloodshot : hint_range(0.0, 1.0) = 0.7;
uniform float eye_glow : hint_range(0.0, 3.0) = 1.2;

// --- Viewport-Aspect (als Uniform setzen: z.B. 16.0/9.0) ---
uniform float viewport_aspect : hint_range(0.5, 4.0) = 1.777;

// ─── Hash / Noise / FBM ───────────────────────────────────────────
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p *= 2.05;
        a *= 0.5;
    }
    return v;
}

// ─── Ellipsen-SDF ────────────────────────────────────────────────
// Gibt signed distance zurück (negativ = innen)
float sdf_ellipse(vec2 p, vec2 ab) {
    p = abs(p);
    if (p.x > p.y) { p = p.yx; ab = ab.yx; }
    float l  = ab.y * ab.y - ab.x * ab.x;
    float m  = ab.x * p.x / l;
    float n  = ab.y * p.y / l;
    float m2 = m * m;
    float n2 = n * n;
    float c  = (m2 + n2 - 1.0) / 3.0;
    float c3 = c * c * c;
    float q  = c3 + m2 * n2 * 2.0;
    float d  = c3 + m2 * n2;
    float g  = m + m * n2;
    float co;
    if (d < 0.0) {
        float h  = acos(q / c3) / 3.0;
        float s  = cos(h);
        float t2 = sin(h) * sqrt(3.0);
        float rx = sqrt(-c * (s + t2 + 2.0) + m2);
        float ry = sqrt(-c * (s - t2 + 2.0) + m2);
        co = (ry + sign(l) * rx + abs(g) / (rx * ry) - m) / 2.0;
    } else {
        float h  = 2.0 * m * n * sqrt(d);
        float s  = sign(q + h) * pow(abs(q + h), 1.0 / 3.0);
        float t2 = sign(q - h) * pow(abs(q - h), 1.0 / 3.0);
        float rx = -(s + t2) - c * 4.0 + 2.0 * m2;
        float ry = (s - t2) * sqrt(3.0);
        float rm = sqrt(rx * rx + ry * ry);
        co = (ry / sqrt(rm - rx) + 2.0 * g / rm - m) / 2.0;
    }
    vec2 r = ab * vec2(co, sqrt(1.0 - co * co));
    return length(r - p) * sign(p.y - r.y);
}

// ─── Auge zeichnen ───────────────────────────────────────────────
vec4 draw_eye(vec2 uv, vec2 center, float size,
              float blink_phase, float gaze_x, float gaze_y, float phase) {

    // Aspect-Korrektur: streckt X so dass Iris als Kreis erscheint
    vec2 p = (uv - center) * vec2(viewport_aspect, 1.0) / size;

    // Äußere Augenhülle: Ellipse 1.8:1 (Breite:Höhe)
    vec2 eye_ab = vec2(1.0, 0.56);

    // Blinzel: beide Lider fahren zur Mitte
    float blink_t  = sin(blink_phase);
    float open_amt = clamp(blink_t * 0.55 + 0.55, 0.02, 1.0);

    // Äußere Ellipse — weiches Alpha
    float eye_sdf   = sdf_ellipse(p, eye_ab);
    float eye_alpha = smoothstep(0.04, -0.02, eye_sdf);

    // Frühzeitig raus wenn weit außerhalb (Performance)
    if (eye_alpha < 0.005) return vec4(0.0);

    // Lider: oberes und unteres Lid schließen sich
    float lid_h    = eye_ab.y * (1.0 - open_amt);
    float lid_top  = smoothstep( lid_h + 0.06,  lid_h - 0.02,  p.y);
    float lid_bot  = smoothstep(-lid_h - 0.06, -lid_h + 0.02, -p.y);
    float lid_mask = lid_top * lid_bot;
    float mask     = eye_alpha * lid_mask;

    // Iris — gleichmäßig rund dank Aspect in p
    vec2  iris_p = p - vec2(gaze_x, gaze_y) * 0.38;
    float iris_r  = length(iris_p);
    float iris    = smoothstep(0.26, 0.22, iris_r);

    // Pupille pulsierend
    float pup_r = 0.10 + sin(phase * 0.7) * 0.018;
    float pupil = smoothstep(pup_r + 0.025, pup_r - 0.005, iris_r);

    // Iris-Detail
    float iris_rings = sin(iris_r * 28.0 + phase * 0.5) * 0.5 + 0.5;
    float iris_fbm   = fbm(iris_p * 10.0 + phase) * 0.45;

    // Blutgefässe in Sklera
    float veins = 0.0;
    for (int i = 0; i < 5; i++) {
        float ang  = float(i) * 1.2566 + phase * 0.12;
        vec2  vd   = vec2(cos(ang), sin(ang));
        float vein = 1.0 - smoothstep(0.0, 0.018,
                       abs(dot(p, vec2(-vd.y, vd.x))) - 0.003);
        veins += vein
               * smoothstep(0.30, 0.20, iris_r)
               * smoothstep(0.04, 0.20, iris_r)
               * eye_bloodshot;
    }

    // Sklera
    float sn      = fbm(p * 7.0 + phase) * 0.1;
    vec3  sclera  = vec3(0.92 + sn, 0.87 + sn, 0.82 + sn);
    sclera        = mix(sclera, vec3(0.88, 0.08, 0.04),
                        clamp(veins, 0.0, 1.0) * 0.8);

    // Iris-Farbe
    vec3 iris_col = mix(vec3(0.60, 0.14, 0.01), vec3(0.85, 0.32, 0.03),
                        clamp(iris_r / 0.24, 0.0, 1.0));
    iris_col = mix(iris_col, vec3(0.22, 0.04, 0.0), iris_fbm);
    iris_col = mix(iris_col, iris_col * (0.7 + iris_rings * 0.3), 0.4);

    // Farben zusammensetzen
    vec3 col = sclera;
    col = mix(col, iris_col,            iris);
    col = mix(col, vec3(0.02, 0.0, 0.0), pupil);

    // Glanzpunkte
    float spec  = 1.0 - smoothstep(0.008, 0.022,
                    length(iris_p - vec2(0.06, -0.07)));
    float glint = 1.0 - smoothstep(0.004, 0.010,
                    length(p - vec2(-0.13, -0.13)));
    col = mix(col, vec3(1.0),           spec * pupil * 0.95);
    col = mix(col, vec3(1.0, 1.0, 0.92), glint);

    // Lidsaum dunkel
    float rim = smoothstep(-0.02, 0.04, eye_sdf) * eye_alpha;
    col = mix(col, vec3(0.04, 0.0, 0.0), rim * 0.7);

    // Blut-Glow innen
    col += vec3(0.5, 0.02, 0.0)
         * smoothstep(0.0, 0.45, 1.0 - iris)
         * smoothstep(0.0, 0.28, 1.0 - pupil)
         * veins * 0.22;

    // Lid-Schatten
    float shadow = smoothstep(0.32, 0.55, abs(p.y / eye_ab.y)) * 0.5;
    col *= 1.0 - shadow * lid_mask;

    return vec4(col, mask);
}

// ─── Nausea-UV-Verzerrung ────────────────────────────────────────
vec2 apply_nausea(vec2 uv, float wt) {
    // Sinuswellen
    uv.x += sin(uv.y * nausea_waves + wt)           * nausea_strength * 0.08;
    uv.y += sin(uv.x * nausea_waves * 1.7 - wt*1.3) * nausea_strength * 0.045;
    // FBM-Distorsion
    uv.x += fbm(uv * 3.0 + vec2(wt, wt * 0.4))      * nausea_strength * 0.06;
    uv.y += fbm(uv * 4.0 - vec2(wt * 0.6, wt))      * nausea_strength * 0.035;
    // Radialer Puls
    vec2 d2 = uv - vec2(0.5);
    uv += normalize(d2 + 0.0001)
        * sin(length(d2) * 14.0 - wt * 2.2)
        * nausea_radial * 0.03;
    // Gitter-Scherung
    uv.x += sin(uv.y * 6.0 + wt * 0.7) * nausea_grid * 0.025;
    uv.y += cos(uv.x * 5.0 - wt * 0.9) * nausea_grid * 0.025;
    return uv;
}

// ─── Augen-Positionen (stabiles Driften) ─────────────────────────
vec2 eye_position(int idx, float t) {
    // 8 fest definierte Positionen — eye_count steuert wie viele aktiv
    vec2 base_positions[8];
    base_positions[0] = vec2(0.50, 0.74);
    base_positions[1] = vec2(0.19, 0.56);
    base_positions[2] = vec2(0.81, 0.52);
    base_positions[3] = vec2(0.34, 0.83);
    base_positions[4] = vec2(0.70, 0.80);
    base_positions[5] = vec2(0.50, 0.38);
    base_positions[6] = vec2(0.12, 0.78);
    base_positions[7] = vec2(0.88, 0.70);

    float fi = float(idx);
    vec2 base = base_positions[idx];
    // organisches Driften pro Auge, verschiedene Frequenzen
    base.x += sin(t * (0.11 + fi * 0.031) + fi * 2.39) * 0.022;
    base.y += cos(t * (0.09 + fi * 0.027) + fi * 1.73) * 0.016;
    return base;
}

// ─── Sky Shader Main ─────────────────────────────────────────────
void sky() {
        // Y-Rotation auf EYEDIR anwenden
    vec3 dir = EYEDIR;
    float cos_r = cos(sky_rotation_y);
    float sin_r = sin(sky_rotation_y);
    dir = vec3(
        dir.x * cos_r + dir.z * sin_r,
        dir.y,
        -dir.x * sin_r + dir.z * cos_r
    );
    float t  = TIME * time_speed;
    float wt = TIME * nausea_speed;

    // 2D Sky-UV aus Kugelrichtung
    float y      = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
    vec2 sky_uv  = vec2(atan(dir.x, dir.z) / 6.28318 + 0.5, y);

    // Nausea-verzerrte UVs für Himmel-Elemente
    vec2 warped = apply_nausea(sky_uv, wt);
    float wy    = clamp(warped.y, 0.0, 1.0);

    // ── Basishimmel ────────────────────────────────────────────
    vec3 base = mix(horizon_color.rgb, zenith_color.rgb,
                    smoothstep(0.12, 1.0, wy));

    // ── Aschewolken ────────────────────────────────────────────
    float clouds     = fbm(warped * cloud_scale
                           + vec2(t * cloud_speed, -t * cloud_speed * 0.35));
    float cloud_mask = smoothstep(0.38, 0.82, clouds * cloud_density);

    // ── Horizontfeuer ──────────────────────────────────────────
    float flame_n = fbm(vec2(
        warped.x * 5.0 + sin(TIME * 0.8) * 0.15,
        warped.y * 2.0 - t * 0.75
    ));
    float horiz_f = smoothstep(horizon_fire_height, 0.0, wy);
    float flame   = horiz_f * smoothstep(0.35, 0.95, flame_n);

    // ── Puls ───────────────────────────────────────────────────
    float pulse = 1.0 + sin(TIME * 2.5) * pulse_strength;

    // ── Farbe aufbauen ─────────────────────────────────────────
    vec3 color = base;
    color = mix(color, ash_color.rgb, cloud_mask * ash_amount);
    color += fire_color.rgb * flame * fire_glow_strength * pulse;

    // ── Portal ─────────────────────────────────────────────────
    vec3 portal_dir = normalize(vec3(
        sin(TIME * 0.35) * nausea_strength * 0.18,
        0.08 + sin(TIME * 0.7) * nausea_strength * 0.05,
        -1.0
    ));
    float pd      = dot(dir, portal_dir);
    float p_outer = smoothstep(1.0 - portal_size * 4.5, 1.0, pd);
    float p_core  = smoothstep(1.0 - portal_size,       1.0, pd);
    color += fire_color.rgb * p_outer * portal_glow * 0.35 * pulse;
    color += vec3(1.0, 0.65, 0.12) * p_core * portal_glow;

    // ── Nausea-Overlays ────────────────────────────────────────
    // 1. Diagonale Dunkelwellen
    float wave_dark = sin((warped.x + warped.y) * 18.0 + TIME * 2.2) * 0.5 + 0.5;
    color = mix(color, vec3(0.02, 0.0, 0.0),
                wave_dark * nausea_strength * 0.22);

    // 2. Radialer Puls
    float radial_pulse = sin(length(sky_uv - vec2(0.5)) * 22.0 - TIME * 3.0) * 0.5 + 0.5;
    color = mix(color, vec3(0.4, 0.02, 0.0),
                radial_pulse * 0.08 * nausea_radial);

    // 3. Gitter-Schimmer
    float grid_flicker = sin(warped.x * 30.0 + TIME * 4.1)
                       * sin(warped.y * 30.0 - TIME * 3.7) * 0.5 + 0.5;
    color = mix(color, vec3(0.35, 0.0, 0.0),
                grid_flicker * nausea_grid * 0.1);

    // 4. Obere Dunkelheit
    color = mix(color, vec3(0.006, 0.0, 0.0),
                smoothstep(0.35, 1.0, wy) * 0.48);

    // 5. Vignette
    float vign = length(sky_uv - vec2(0.5));
    color *= 1.0 - vign * vign * 0.55;

    // ── Augen ─────────────────────────────────────────────────
    // Augen-UV: leichtes eigenes Wackeln, aber NICHT die starke
    // Himmel-Nausea — verhindert harte Cuts an UV-Grenzen
    vec2 eye_uv = sky_uv;
    eye_uv.x += sin(eye_uv.y * nausea_waves * 0.5 + wt * 0.4)
                * nausea_strength * 0.012;
    eye_uv.y += sin(eye_uv.x * nausea_waves * 0.8 - wt * 0.5)
                * nausea_strength * 0.008;

    for (int i = 0; i < 8; i++) {
        if (i >= eye_count) break;

        float fi      = float(i);
        vec2  eye_pos = eye_position(i, TIME);

        // Blinzeln: versetzt + unregelmäßig pro Auge
        float blink = TIME * (eye_blink_speed + fi * 0.18)
                    + sin(TIME * (0.28 + fi * 0.09) + fi * 1.1) * 2.8;

        // Blick dreht sich langsam, unabhängig pro Auge
        float gaze_x = sin(TIME * (0.25 + fi * 0.08) + fi * 1.57)
                     * eye_gaze_range;
        float gaze_y = cos(TIME * (0.31 + fi * 0.07) + fi * 2.09)
                     * eye_gaze_range * 0.65;

        float phase = fi * 1.234 + TIME * 0.08;

        // Glow unter jedem Auge (weicher Schein, kein cut)
        vec2  gp = (eye_uv - eye_pos) * vec2(viewport_aspect, 1.0);
        float gd = length(gp) / (eye_size * (0.8 + fi * 0.04));
        color += fire_color.rgb * eye_glow * 0.28
               * exp(-gd * gd * 0.7) * pulse;

        // Auge zeichnen und weich alpha-blenden
        float s      = eye_size * (0.8 + fi * 0.04);
        vec4  eye_c  = draw_eye(eye_uv, eye_pos, s,
                                blink, gaze_x, gaze_y, phase);
        // mix() = kein hartes clip, kein sichtbarer Schnitt beim Überlappen
        color = mix(color, eye_c.rgb, eye_c.a);
    }

    COLOR = color;
}