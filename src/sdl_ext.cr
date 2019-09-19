lib LibSDL
  fun SDL_GetTicks : UInt32
end

module SDL
  PIXELFORMAT_8888 = (1_u32 << 28) |
                     (6_u32 << 24) | # PIXELTYPE_PACKED32
                     (8_u32 << 20) |
                     # (3_u32 << 20) |
                     (6_u32 << 16) | # PACKEDLAYOUT_8888
                     (32_u32 << 8) | # bits
                     (4_u32 << 0)    # bytes

  def self.ticks
    LibSDL.SDL_GetTicks
  end

  struct Event
    def self.poll
      while event = SDL::Event.poll
        yield event
      end
    end
  end

  class Texture
    def self.new(renderer : Renderer, format : UInt32, access : Int, w : Int, h : Int)
      texture = LibSDL.create_texture(renderer, format, access, w, h)
      raise Error.new("SDL_CreateTextureFromSurface") unless texture
      new(texture)
    end

    def lock(rect, pixels : Void**, pitch : Int32*) : Nil
      value = LibSDL.lock_texture(self, nil, pixels, pitch)
      raise Error.new("SDL_LockTexture") if value != 0
    end

    def unlock
      LibSDL.unlock_texture(self)
    end
  end
end
