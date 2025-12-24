// Bindless helpers

[[vk::binding(0, 0)]] __DynamicResource g_textures[];
[[vk::binding(1, 0)]] __DynamicResource g_rw_textures[];
[[vk::binding(2, 0)]] SamplerState g_samplers[];

public struct SamplerHandle {
    uint descriptor_index;
    public property SamplerState Instance {
        [ForceInline]
        get { return g_samplers[descriptor_index]; }
    }
}

interface IImageDescriptor {
    static const bool is_writeable;
}

public struct ImageHandle<T: IImageDescriptor & __IDynamicResourceCastable> {
    uint descriptor_index;

    public property T Instance {
        [ForceInline]
        get { return (T.is_writeable ? g_rw_textures : g_textures)[descriptor_index].as<T>(); }
    }
}

__generic<E : ITexelElement, Shape : __ITextureShape, int is_array, int is_ms, int sample_count, int access, int is_shadow, int format>
extension _Texture<E, Shape, is_array, is_ms, sample_count, access, is_shadow, 0, format> : IImageDescriptor {
    static const bool is_writeable = access == 1;
};

__generic<E : ITexelElement, Shape : __ITextureShape, let format : int>
public extension ImageHandle<_Texture<E, Shape, 0, 0, 0, 1, 0, 0, format>> {
    typealias TextureType = _Texture<E, Shape, 0, 0, 0, 1, 0, 0, format>;

    [ForceInline]
    public E Load(vector<uint, Shape.dimensions> pos) {
        return Instance[pos];
    }
    [ForceInline]
    public void Store(vector<uint, Shape.dimensions> pos, E value) {
        Instance[pos] = value;
    }
}


public typealias TextureHandle2D<F: ITexelElement = float4> = ImageHandle<Texture2D<F>>;
public typealias TextureHandle3D<F: ITexelElement = float4> = ImageHandle<Texture3D<F>>;
public typealias RWTextureHandle2D<F: ITexelElement = float4> = ImageHandle<RWTexture2D<F>>;
public typealias RWTextureHandle3D<F: ITexelElement = float4> = ImageHandle<RWTexture3D<F>>;

public typealias RWTextureCube<F: ITexelElement = float4> = _Texture<F, __ShapeCube, 0, 0, 0, 1, 0, 0, 0>;

public typealias TextureHandleCube<F: ITexelElement = float4> = ImageHandle<TextureCube<F>>;
public typealias ImageHandleCube<F: ITexelElement = float4> = ImageHandle<RWTextureCube<F>>;