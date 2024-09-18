# Constants
PLAYER_HEALTH     = 5
PLAYER_MOVE_SPEED = 5
ENEMY_MOVE_SPEED  = 3
SCORE_PER_KILL    = 10
GRID_DIMENSION    = 32
CELL_SIZE         = 40
WORLD_SIZE        = GRID_DIMENSION * CELL_SIZE

def init args
  args.state.player  = {x: 0, y: 0, w: 80, h: 80, path: 'sprites/circle/white.png', vx: 0, vy: 0, health: PLAYER_HEALTH, cooldown: 0, score: 0}
  args.state.enemies = []
  args.state.world   = WorldGrid.new args, GRID_DIMENSION, CELL_SIZE
  puts "Initialized"

  ploc = args.state.world.coord_to_cell_center 10,10
  args.state.player.x, args.state.player.y = ploc.x, ploc.y
end

def tick args
  # Initialize/reinitialize
  if !args.state.initialized
    init args
    args.state.initialized = true
  end

  # Execute current game state
  if args.state.current_state
    args.state.current_state.args = args
    args.state.current_state.tick
  else
    # Not refactored into state yet
    spawn_enemies args
    collide_enemies args
    move_enemies args
    move_player args
    # player attack

    # Game over check
    if args.state.player.health <= 0
      args.state.current_state = State_Gameover.new args
    end

    # Render world
    args.state.world.render_grid_lines

    # Render characters
    args.outputs.sprites << [args.state.player, args.state.enemies]

    render_hud args
  end

  # Debug keys
  # Reset
  if args.inputs.keyboard.key_down.r
    $gtk.reset_next_tick
  end

  # Debug stats
  args.outputs.labels << { x: 10, y: 70.from_top, r: 255, g: 255, b: 255, size_enum: -2, text: "FPS: #{args.gtk.current_framerate.to_sf}" }
end

def spawn_enemies args
  # Spawn enemies more frequently as the player's score increases.
  if rand < (100+args.state.player[:score])/(10000 + args.state.player[:score]) || Kernel.tick_count.zero?
    theta = rand * Math::PI * 2
    args.state.enemies << {
        x: 600 + Math.cos(theta) * 800, y: 320 + Math.sin(theta) * 800, w: 80, h: 80,
        path: 'sprites/circle/white.png',
        r: (256 * rand).floor, g: (256 * rand).floor, b: (256 * rand).floor
    }
  end
end

# Collide enemies with player (they die in 1 hit and damage player)
def collide_enemies args
  args.state.enemies.reject! do |enemy|
    # Check if enemy and player are within 80 pixels of each other (i.e. overlapping)
    if 6400 > (enemy.x - args.state.player.x) ** 2 + (enemy.y - args.state.player.y) ** 2
      # Enemy is touching player. Kill enemy, and reduce player HP by 1.
      args.state.player[:health] -= 1
      give_score SCORE_PER_KILL
    else
      # Player bullet/attack collisions
    end
  end
end

# Move enemies towards player. Use the current grid cell's vector
# to move towards player's location, at close range use more precise
# Direction towards player.
def move_enemies args
  args.state.enemies.each do |enemy|
    # Get the angle from the enemy to the player
    theta   = Math.atan2(enemy.y - args.state.player.y, enemy.x - args.state.player.x)
    # Convert the angle to a vector pointing at the player
    dx, dy  = theta.to_degrees.vector ENEMY_MOVE_SPEED
    # Move the enemy towards thr player
    enemy.x -= dx
    enemy.y -= dy
  end
end

def move_player args
  if args.inputs.directional_angle
    args.state.player.x += args.inputs.directional_angle.vector_x * PLAYER_MOVE_SPEED
    args.state.player.y += args.inputs.directional_angle.vector_y * PLAYER_MOVE_SPEED
    #args.state.player.x  = args.state.player.x.clamp(0, args.state.world.w - args.state.player.size)
    #args.state.player.y  = args.state.player.y.clamp(0, args.state.world.h - args.state.player.size)
  end
end

def render_hud args
  args.outputs.labels << { x: 10, y: 90.from_top,
    r: 255, g: 255, b: 255, size_enum: -2,
    text: "Health: #{args.state.player.health}"
  }

  args.outputs.labels << { x: 100, y: 90.from_top,
    r: 255, g: 255, b: 255, size_enum: -2,
    text: "Score: #{args.state.player.score}"
  }
end

def give_score amount
  $args.state.player.score += amount
end

class State_Gameover
  attr_gtk

  def initialize args
    self.args = args
  end

  def tick
    outputs.labels << { x: 140, y: 130.from_top,
      r: 255, g: 255, b: 49, size_enum: 2,
      text: "GEIM OVER, HIT R TO RESTART"
    }
  end
end

class WorldGrid
  attr_gtk
  attr_reader :width
  attr_reader :height
  attr_reader :cell_size
  attr_reader :inv_cell_size
  attr_reader :origin

  def initialize args, dimension, cell_size
    @args = args
    @width         = dimension
    @height        = dimension
    @cell_size     = cell_size
    @inv_cell_size = 1 / cell_size
    @origin        = { x: 0, y: 0 }

    @cell_half_size     = @cell_size / 2
  end

  # Grid x,y location to array index
  def index_to_coord index
    x = index % @width
    y = index/ @width
    { x: x, y: y }
  end

  # Grid array index to x,y coordinate
  def coord_to_index x, y
    x + @width * y
  end

  # World coordinate (float) to cell x,y
  def world_to_coord world_x, world_y
    local_x  = world_x - @origin.x
    local_y  = world_y - @origin.y
    i = (local_x * @inv_cell_size).floor
    j = (local_y * @inv_cell_size).floor
    { x: i, y: j }
  end

  # Cell center location in world coordinates
  def coord_to_cell_center x,y
    local_x = x.clamp(0, @width - 1)
    local_y = y.clamp(0, @height - 1)
    { x: @origin.x + local_x * @cell_size + @cell_half_size, y: @origin.y + local_y * @cell_size + @cell_half_size }
  end

  # Debug draw functions
  def render_grid_lines
    outputs.lines << (0..@width).map { |x| vertical_line(x) }
    outputs.lines << (0..@height).map { |y| horizontal_line(y) }
  end

  def horizontal_line y
    line = { x: 0, y: y, w: @width, h: 0 }
    line.transform_values { |v| v * @cell_size }
  end
  
  def vertical_line x
    line = { x: x, y: 0, w: 0, h: @height }
    line.transform_values { |v| v * @cell_size }
  end
end