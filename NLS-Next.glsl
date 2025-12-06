//	NLS-Next by NotMithical
//	https://github.com/NotMithical/MPV-NLS-Next/blob/main/NLS-Next.glsl
//
// --Parameters Summary --
// HorizontalStretch and VerticalStretch:
//		Adjust balance between Horizontal and Vertical Stretching. Values will be normalized to total to 1.0, otherwise distortion will occur in the center of the image.
// CropAmount:
//		Crop image edges. Raising this value results in loss of content but results in less stretching.
// BarsAmount:
//		Scale the image down and add padding in the form of black bars. Raising this value results in less stretching.
// CenterProtect:
//		Changes the curve for stretching. Higher values apply more stretching towards the edges of the screen. Currently experimental; I'm still figuring out the math for this whole thing and it turns out the padding, cropping, and center protection affect each other a fair bit.
//
// dest_height & dest_width are set by the NLS-Next.lua helper script. Changing their values here will have no effect.
//
// The defaults will distribute stretching across all edges and will not crop or pad the image.

//!PARAM HorizontalStretch
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.5

//!PARAM VerticalStretch
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.5

//!PARAM CropAmount
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.0

//!PARAM BarsAmount
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.0

//!PARAM CenterProtect
//!TYPE float
//!MINIMUM 0.1
//!MAXIMUM 6.0
1.0

//!PARAM dest_width
//!TYPE int
//!MINIMUM 0
//!MAXIMUM 99999
0

//!PARAM dest_height
//!TYPE int
//!MINIMUM 0
//!MAXIMUM 99999
0

//!HOOK MAIN
//!BIND HOOKED
//!HEIGHT dest_height
//!WHEN dest_height MAIN.h > OUTPUT.w OUTPUT.h / dest_width dest_height / = ! *
//!DESC NLS-Next Prescale Vert

#define R 3.0 //kernel radius, (0.0, 10.0+]
#define B 0.9812505644269356 //kernel blur, 1.0 means no effect, (0.0, 1.5+]
#define AR 0.6 //antiringing strength, [0.0, 1.0]

#define M_PI 3.14159265358979323846
#define M_PI_2 1.57079632679489661923
#define EPSILON 1.192093e-7

#define sinc(x) (x < EPSILON ? M_PI : sin(M_PI / B * x) * B / x)

#define k(x) (sinc(x) * (x < EPSILON ? M_PI : sin(M_PI / R * x) * R / x))

#define get_weight(x) (x < R ? k(x) : 0.0)

vec4 hook() {
    float fcoord = fract(HOOKED_pos.y * input_size.y - 0.5);
    vec2 base = HOOKED_pos - fcoord * HOOKED_pt * vec2(0.0, 1.0);
    vec4 color;
    float weight;
    vec4 csum = vec4(0.0);
    float wsum = 0.0;
    vec4 low = vec4(1e9);
    vec4 high = vec4(-1e9);
    for (float i = 1.0 - ceil(R); i <= ceil(R); ++i) {
        weight = get_weight(abs(i - fcoord));
        color = textureLod(HOOKED_raw, base + HOOKED_pt * vec2(0.0, i), 0.0) * HOOKED_mul;
        csum += color * weight;
        wsum += weight;
        if (AR > 0.0 && i >= 0.0 && i <= 1.0) {
            low = min(low, color);
            high = max(high, color);
        }
    }
    csum /= wsum;
    if (AR > 0.0)
        csum = mix(csum, clamp(csum, low, high), AR);
    return csum;
}
//!HOOK MAIN
//!BIND HOOKED
//!WIDTH dest_width
//!WHEN dest_width MAIN.w > OUTPUT.w OUTPUT.h / dest_width dest_height / = ! *
//!DESC NLS-Next Prescale Horiz

#define R 3.0 //kernel radius, (0.0, 10.0+]
#define B 0.9812505644269356 //kernel blur, 1.0 means no effect, (0.0, 1.5+]
#define AR 0.6 //antiringing strength, [0.0, 1.0]

#define M_PI 3.14159265358979323846
#define M_PI_2 1.57079632679489661923
#define EPSILON 1.192093e-7

#define sinc(x) (x < EPSILON ? M_PI : sin(M_PI / B * x) * B / x)

#define k(x) (sinc(x) * (x < EPSILON ? M_PI : sin(M_PI / R * x) * R / x))

#define get_weight(x) (x < R ? k(x) : 0.0)

vec4 hook() {
    float fcoord = fract(HOOKED_pos.x * input_size.x - 0.5);
    vec2 base = HOOKED_pos - fcoord * HOOKED_pt * vec2(1.0, 0.0);
    vec4 color;
    float weight;
    vec4 csum = vec4(0.0);
    float wsum = 0.0;
    vec4 low = vec4(1e9);
    vec4 high = vec4(-1e9);
    for (float i = 1.0 - ceil(R); i <= ceil(R); ++i) {
        weight = get_weight(abs(i - fcoord));
        color = textureLod(HOOKED_raw, base + HOOKED_pt * vec2(i, 0.0), 0.0) * HOOKED_mul;
        csum += color * weight;
        wsum += weight;
        if (AR > 0.0 && i >= 0.0 && i <= 1.0) {
            low = min(low, color);
            high = max(high, color);
        }
    }
    csum /= wsum;
    if (AR > 0.0)
        csum = mix(csum, clamp(csum, low, high), AR);
    return csum;
}

//!HOOK MAIN
//!BIND HOOKED
//!WHEN OUTPUT.w OUTPUT.h / dest_width dest_height / = !
//!DESC NLS-Next Stretch

vec2 stretch(vec2 pos, float h_par, float v_par) {
	// Normalize user defined parameters
	float HorizontalStretchNorm = (HorizontalStretch * (1 / (HorizontalStretch + VerticalStretch))),
		  VerticalStretchNorm = (VerticalStretch * (1 / (HorizontalStretch + VerticalStretch)));

	float h_m_stretch = pow(h_par, HorizontalStretchNorm),
		  v_m_stretch = pow(v_par, VerticalStretchNorm),
		  x = pos.x - 0.5,
		  y = pos.y - 0.5;

	// Map x & y coordinates to themselves with a curve, taking into account cropping and padding
	if (h_par < 1) {
		return vec2(mix(x * pow(abs(x), CenterProtect) * (pow(2, CenterProtect) - (CropAmount * 2)), x, h_m_stretch) + 0.5, mix(y * pow(abs(y), CenterProtect) * (pow(2, CenterProtect) - (BarsAmount * 5)), y, v_m_stretch) + 0.5);
	} else {
		return vec2(mix(x * pow(abs(x), CenterProtect) * (pow(2, CenterProtect) - (BarsAmount * 5)), x, h_m_stretch) + 0.5, mix(y * pow(abs(y), CenterProtect) * (pow(2, CenterProtect) - (CropAmount * 2)), y, v_m_stretch) + 0.5);
	}
}

vec4 hook() {
	float dar = target_size.x / target_size.y,
		  sar = HOOKED_size.x / HOOKED_size.y,
		  h_par = dar / sar,
		  v_par = sar / dar;

	vec2 stretchedPos = stretch(HOOKED_pos, h_par, v_par);

	// Check what pixels are outside the target boundaries
	bool outOfBounds = ((any(lessThan(stretchedPos, vec2(0.0))) || any(greaterThan(stretchedPos, vec2(1.0)))) ? true : false);

	// Black out pixels outside target boundaries
	return (outOfBounds ? vec4(0.0) : HOOKED_tex(stretchedPos));
}
