import "common";
import "bindless";

struct PS_Input {
  float2 uv : TEXCOORD0;
}

struct PS_Params {
  TextureHandle2D texture;
  SamplerHandle sampler;
}

[vk::push_constant]
PixelParams<PS_Params> p;

[shader("pixel")]
float4 main(PS_Input input) : SV_Target0 {
  PS_Params params = *p.get();
  return float4(params.texture.Sample(params.sampler, input.uv));
}
