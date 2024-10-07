# Interpolation stuff

def lerp v0, v1, t
  return (1 - t) * v0 + t * v1
end

def smoothstep v0, v1, t
  raise "#{t} vs #{v1}" if t > v1
  p = ((t - v0) / (v1 - v0)).cap_min_max(0,1)
  return p * p * (3 - 2 * p)
end

def pow n, to
  n ** to
end

class Curve
  attr_accessor :frames
  attr_accessor :mode

  # Make an empty curve
  # Initialize from time/value array: [[0.0, 10], [0.5, 20], [1.0, 100]...]
  def initialize mode = :linear, frame_array = nil
    @frames = []
    @mode   = mode
    if frame_array
      raise "Needs an array" unless frame_array.is_a?(Array)
      raise "Array needs at least 2 points" unless frame_array.length >= 2
      @frames = frame_array.map {|t,v| {time: t, value: v} }
      @frames = @frames.sort_by { |x| x.time }
    end
  end

  def start_time
    return 0 if @frames.length < 1
    return @frames[0].time
  end

  def end_time
    return 0 if @frames.length < 1
    return @frames[-1].time
  end

  def calculate_max
    max = -1e6
    @frames.each do |f|
      max = max.greater(f.value)
    end
    return max
  end

  # Add a keyframe and sort the keys by time
  def add_frame! time, value
    @frames << { time: time, value: value }
    @frames = @frames.sort_by { |x| x.time }
  end

  # Evaluates the value for a given time
  def evaluate time
    return 0 if @frames.length < 1

    # Out of bounds checks
    if time <= @frames[0].time
      return @frames[0].value
    elsif time >= @frames[-1].time
      return @frames[-1].value
    else # Interpolate between two keyframes
      # Find the 'slice' the current time is in
      start_idx = 0
      @frames.each_with_index do |frame, idx|
        if time >= frame.time
          start_idx = idx
        end
      end

      # Interpolate between start and end
      end_idx = start_idx + 1

      duration = @frames[end_idx].time - @frames[start_idx].time
      elapsed  = time - @frames[start_idx].time
      y = elapsed.percentage_of(duration) #already clamped

      if @mode == :smoothstep
        p = smoothstep(0,1,y)
        return lerp(@frames[start_idx].value, @frames[end_idx].value, p)
      elsif @mode == :quadratic
        p = y
        m = p - 1
        t = p * 2
        if t < 1
          p = p * t * t
        else
          p = 1 + m * m * m * 4;
        end
        return lerp(@frames[start_idx].value, @frames[end_idx].value, p)
      else
        return lerp(@frames[start_idx].value, @frames[end_idx].value, y)
      end
    end
  end
end
