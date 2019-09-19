require "sdl"
require "./sdl_ext"

class Point
  MAX_LIFE  = 50
  HALF_LIFE = MAX_LIFE / 2

  property x : Float64
  property y : Float64
  property angle : Float64
  property speed : Float64
  property color_pattern : ColorPattern
  getter :life

  def initialize(x, y, angle, speed, color_pattern)
    @x = x.to_f64
    @y = y.to_f64
    @angle = angle.to_f64
    @speed = speed.to_f64
    @color_pattern = color_pattern
    @life = MAX_LIFE
  end

  def dead?
    @life <= 0
  end

  def revive
    @life = MAX_LIFE
  end

  def die_a_little
    @life -= 1
  end

  def color
    @color_pattern.interpolate(@life)
  end

  def advance(screen)
    @x += @speed * Math.cos(@angle)
    @y -= @speed * Math.sin(@angle)

    if @x <= 0
      @angle = Math::PI - @angle
      @x = 0_f64
    end

    if @x >= screen.width - 1
      @angle = Math::PI - @angle
      @x = (screen.width - 1).to_f64
    end

    if @y <= 0
      @angle = 2 * Math::PI - @angle
      @y = 0_f64
    end

    if @y >= screen.height - 1
      @angle = 2 * Math::PI - @angle
      @y = (screen.height - 1).to_f64
    end
  end
end

class MainPoint < Point
  COUNT          = 4
  MAX_TAIL_ANGLE = Math::PI / 3
  TAIL_SPEED     = 0.05

  @tail_angle : Float64

  def initialize(x, y, angle, speed, color_pattern)
    super
    @tail_angle = MAX_TAIL_ANGLE
    @tail_direction = :minus
    @color_pattern = color_pattern
  end

  def turn_left
    @angle += 0.05
  end

  def turn_right
    @angle -= 0.05
  end

  def speed_up
    @speed += 0.02
    @speed = 20_f64 if @speed >= 20
  end

  def speed_down
    @speed -= 0.02
    @speed = 0_f64 if @speed <= 0
  end

  def color
    @color_pattern.main
  end

  def emit_tail_points(points)
    points.make(@x, @y, Math::PI + @angle + @tail_angle, @speed, @color_pattern.child)
    points.make(@x, @y, Math::PI + @angle - @tail_angle, @speed, @color_pattern.child)

    if @tail_direction == :plus
      @tail_angle += TAIL_SPEED
      if @tail_angle >= MAX_TAIL_ANGLE
        @tail_angle = MAX_TAIL_ANGLE
        @tail_direction = :minus
      end
    else
      @tail_angle -= TAIL_SPEED
      if @tail_angle <= -MAX_TAIL_ANGLE
        @tail_angle = -MAX_TAIL_ANGLE
        @tail_direction = :plus
      end
    end
  end
end

abstract class ColorPattern
  def child
    self
  end

  def interpolate_half(life)
    (life * 255.0 / Point::HALF_LIFE).to_i
  end

  def interpolate_max(life)
    (life * 255.0 / Point::MAX_LIFE).to_i
  end

  def make_color(r, g, b)
    (b << 24) + (g << 16) + (r << 8)
  end
end

class YellowColorPattern < ColorPattern
  def main
    0x00FFFF00
  end

  def interpolate(life)
    if life > Point::HALF_LIFE
      r, g, b = 255, interpolate_half(life), 0
    else
      r, g, b = interpolate_half(life), 0, 0
    end
    make_color r, g, b
  end
end

class CyanColorPattern < ColorPattern
  def main
    0xFFFF0000
  end

  def interpolate(life)
    if life > Point::HALF_LIFE
      r, g, b = 0, 255, interpolate_half(life)
    else
      r, g, b = 0, interpolate_half(life), 0
    end
    make_color r, g, b
  end
end

class MagentaColorPattern < ColorPattern
  def main
    0xFF00FF00
  end

  def interpolate(life)
    if life > Point::HALF_LIFE
      r, g, b = interpolate_half(life), 0, 255
    else
      r, g, b = 0, 0, interpolate_half(life)
    end
    make_color r, g, b
  end
end

class RainbowColorPattern < ColorPattern
  def initialize(@patterns : Array(ColorPattern))
    @index = 0.0
  end

  def main
    main = @patterns[@index.to_i].main
    @index += 0.05
    @index = 0.0 if @index.to_i >= @patterns.size
    main
  end

  def child
    @patterns[@index.to_i]
  end

  def interpolate(life)
    raise "shouldn't reach here"
  end
end

class Points
  MAX = Point::MAX_LIFE * MainPoint::COUNT * 2

  def initialize
    @points = Array(Point).new(MAX)
  end

  def make(x, y, angle, speed, color_pattern)
    @points.each do |point|
      if point.dead?
        point.x = x
        point.y = y
        point.angle = angle
        point.speed = speed
        point.color_pattern = color_pattern
        point.revive
        return
      end
    end

    if @points.size < MAX
      @points << Point.new(x, y, angle, speed, color_pattern)
    end
  end

  def each
    @points.each do |point|
      yield point unless point.dead?
    end
  end
end

record Rectangle, x : Int32, y : Int32 do
  def contains?(p)
    contains? p.x, p.y
  end

  def contains?(x, y)
    @x <= x && x < @x + 10 && @y <= y && y < @y + 10
  end
end

def parse_rectangles(filename)
  unless File.exists?(filename)
    raise "File does not exist: #{filename}"
  end

  rects = [] of Rectangle
  lines = File.read(filename)
  lines = lines.split('\n').map { |line| line.rstrip }
  lines.each_with_index do |line, y|
    x = 0
    line.each_char do |c|
      if c != ' '
        rects << Rectangle.new(x * 10, y * 10)
      end
      x += 1
    end
  end
  rects
end

class Screen
  @rects : Array(Rectangle)

  def initialize(@surface : Pointer(Pointer(UInt32)), @width : Int32, @height : Int32)
    @background = Array(UInt32).new(@width * @height, 0_u32)
    @rects = parse_rectangles("#{__DIR__}/fire.txt")
  end

  getter width, height

  def put_pixel(point, color)
    color = color.to_u32!
    offset = @width * point.y.to_i + point.x.to_i
    @surface.value[offset] = color

    background_intensity = intensity(@background[offset])
    color_intensity = intensity(color)

    if color_intensity >= background_intensity && @rects.any?(&.contains?(point))
      @background[offset] = color
    end
  end

  def put_background(point)
    offset = @width * point.y.to_i + point.x.to_i
    @surface.value[offset] = @background[offset]
  end

  def intensity(color)
    b = (color >> 24) % 256
    g = (color >> 16) % 256
    r = (color >> 8) % 256
    r + g + b
  end
end

def finish(start, frames)
  ms = SDL.ticks - start
  puts "#{frames} frames in #{ms} ms"
  puts "Average FPS: #{frames / (ms * 0.001)}"
  SDL.quit
  exit
end

width = 640
height = 480
point_count = ARGV.size > 0 ? ARGV[0].to_i : 4

yellow = YellowColorPattern.new
magenta = MagentaColorPattern.new
cyan = CyanColorPattern.new
rainbow = RainbowColorPattern.new [yellow, magenta, cyan]

main_points = [] of MainPoint
main_points << MainPoint.new(50, 50, -Math::PI / 8, 1.4, yellow)
main_points << MainPoint.new(width - 50, height - 50, Math::PI - Math::PI / 8, 1.4, magenta) if point_count >= 2
main_points << MainPoint.new(width - 50, 50, Math::PI + Math::PI / 8, 1.4, cyan) if point_count >= 3
main_points << MainPoint.new(50, height - 50, Math::PI / 8, 1.4, rainbow) if point_count >= 4

points = Points.new

SDL.init(SDL::Init::VIDEO)
window = SDL::Window.new("Fire", width, height, flags: SDL::Window::Flags.flags(SHOWN, RESIZABLE))
renderer = SDL::Renderer.new(window, SDL::Renderer::Flags::ACCELERATED | SDL::Renderer::Flags::PRESENTVSYNC)
texture = SDL::Texture.new(renderer, SDL::PIXELFORMAT_8888, LibSDL::TextureAccess::STREAMING.value, width, height)
pixels = Pointer(UInt32).malloc(width * height)
pitch = width * 4

screen = Screen.new(pointerof(pixels), width, height)

frames = 0_u32
start = SDL.ticks

turn_left = Array.new(MainPoint::COUNT, false)
turn_right = Array.new(MainPoint::COUNT, false)
speed_up = Array.new(MainPoint::COUNT, false)
speed_down = Array.new(MainPoint::COUNT, false)
quit = false

loop do
  SDL::Event.poll do |event|
    case event
    when SDL::Event::Quit
      finish start, frames
      quit = true
    when SDL::Event::Keyboard
      case event
      when .keydown?
        case event.sym
        when .escape?, .q?
          finish start, frames
          quit = true
        when .left?
          turn_left[0] = true
        when .right?
          turn_right[0] = true
        when .up?
          speed_up[0] = true
        when .down?
          speed_down[0] = true
        when .w?
          speed_up[1] = true
        when .a?
          turn_left[1] = true
        when .s?
          speed_down[1] = true
        when .d?
          turn_right[1] = true
        when .t?
          speed_up[2] = true
        when .f?
          turn_left[2] = true
        when .g?
          speed_down[2] = true
        when .h?
          turn_right[2] = true
        when .i?
          speed_up[3] = true
        when .j?
          turn_left[3] = true
        when .k?
          speed_down[3] = true
        when .l?
          turn_right[3] = true
        end
      when .keyup?
        case event.sym
        when .left?
          turn_left[0] = false
        when .right?
          turn_right[0] = false
        when .up?
          speed_up[0] = false
        when .down?
          speed_down[0] = false
        when .w?
          speed_up[1] = false
        when .a?
          turn_left[1] = false
        when .s?
          speed_down[1] = false
        when .d?
          turn_right[1] = false
        when .t?
          speed_up[2] = false
        when .f?
          turn_left[2] = false
        when .g?
          speed_down[2] = false
        when .h?
          turn_right[2] = false
        when .i?
          speed_up[3] = false
        when .j?
          turn_left[3] = false
        when .k?
          speed_down[3] = false
        when .l?
          turn_right[3] = false
        end
      end
    end
  end

  break if quit

  texture.lock(nil, pointerof(pixels).as(Void**), pointerof(pitch))

  points.each do |point|
    screen.put_background(point)
    point.die_a_little
  end

  main_points.each do |main_point|
    screen.put_background(main_point)
  end

  main_points.each_with_index do |main_point, i|
    main_point.turn_left if turn_left[i]
    main_point.turn_right if turn_right[i]
    main_point.speed_up if speed_up[i]
    main_point.speed_down if speed_down[i]
    main_point.advance(screen)
  end

  points.each do |point|
    point.advance(screen)
  end

  points.each do |point|
    screen.put_pixel(point, point.color)
  end

  main_points.each do |main_point|
    screen.put_pixel(main_point, main_point.color)
  end

  main_points.each do |main_point|
    main_point.emit_tail_points(points)
  end

  texture.unlock

  renderer.clear
  renderer.copy(texture)
  renderer.present

  frames += 1
end
