struct VertexParams<T> {
  [[vk::offset(0)]]
  Ptr<T, Access.Immutable> data;

  [ForceInline]
  Ptr<T, Access.Immutable> get() { return data; }
};

struct PixelParams<T> {
  [[vk::offset(8)]]
  Ptr<T, Access.Immutable> data;

  [ForceInline]
  Ptr<T, Access.Immutable> get() { return data; }
};

struct ComputeParams<T> {
  [[vk::offset(16)]]
  Ptr<T, Access.Immutable> data;

  [ForceInline]
  Ptr<T, Access.Immutable> get() { return data; }
};
