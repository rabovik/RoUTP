#if !OS_OBJECT_USE_OBJC
    #define rou_dispatch_property_qualifier assign
    #define rou_dispatch_retain(object) dispatch_retain(object)
    #define rou_dispatch_release(object) dispatch_release(object)
#else
    #define rou_dispatch_property_qualifier strong
    #define rou_dispatch_retain(object)
    #define rou_dispatch_release(object)
#endif

#define ROUThrow(REASON,...)                                                             \
    @throw ([NSException                                                                 \
            exceptionWithName:@"ROUException"                                            \
            reason:[NSString stringWithFormat:REASON,##__VA_ARGS__]                      \
            userInfo:nil])


