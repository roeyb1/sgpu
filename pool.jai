#scope_module

Pool :: struct(Handle_Type: Type, Value_Type: Type, max: s64 = S64_MAX) {
    values: [..] Value_Type;
    free_list: [..] s64;
    allocator: Allocator;
}

pool_add :: (using pool: *Pool, item: pool.Value_Type) -> pool.Handle_Type {
    if free_list.count > 0 {
        index := pop(*free_list);
        values[index] = item;
        return (index + 1).(pool.Handle_Type);
    } else if values.count < pool.max {
        array_add(*values, item,, allocator);
        return values.count.(pool.Handle_Type);
    } else {
        return 0;
    }
}

pool_remove :: (using pool: *Pool, handle: pool.Handle_Type) -> bool, pool.Value_Type {
    index := (handle - 1).(s64);
    if index < 0 || index >= values.count {
        default_v: pool.Value_Type;
        return false, default_v;
    }
    array_add(*free_list, index,, allocator);
    return true, values[index];
}

pool_get :: (using pool: Pool, handle: pool.Handle_Type) -> *pool.Value_Type {
    index := (handle - 1).(s64);
    if index < 0 || index >= values.count {
        return null;
    }
    return *values[index];
}