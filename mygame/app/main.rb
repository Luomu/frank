# Avoid or fight villagers
# Collect bolts to grow stronger
# Survive as long as you can
#
# TODO:
# - Player attacks
# - Collect bolts to level up and attack faster & stronger
# - Collect electricity to heal
# - More optimized collision between enemies
# - Scrolling
# - Obstacles
# - Perf: refactor sprites to use classes

# Constants
PLAYER_HEALTH     = 5
PLAYER_MOVE_SPEED = 5
PLAYER_ATTACK_COOLDOWN = 65 # default, in ticks
ENEMY_MOVE_SPEED  = 1.5
SCORE_PER_KILL    = 10
GRID_DIMENSION    = 32
CELL_SIZE         = 40
WORLD_SIZE        = GRID_DIMENSION * CELL_SIZE

ENEMY_RADIUS         = 50
ENEMY_COLLIDE_RADIUS = (ENEMY_RADIUS + ENEMY_RADIUS) / 2.0
ENEMY_SPRITE_HEIGHT  = 42
ENEMY_SPRITE_WIDTH   = 32
PLAYER_SPRITE_WIDTH  = 32
PLAYER_SPRITE_HEIGHT = 48
PLAYER_COLLIDE_RADIUS_SQ = 35 * 35

module Cheats
  GODMODE = true
end

PLAYER_START = { x: 10, y: 10 }

North     = 0
NorthEast = 1
East      = 2
SouthEast = 3
South     = 4
SouthWest = 5
West      = 6
NorthWest = 7

DirectionLookup = [
  {x: 0, y: 1},   # N
  {x: 1, y: 1},   # NE
  {x: 1, y: 0},   # E
  {x: 1, y: -1},  # SE
  {x: 0, y: -1},  # S
  {x: -1, y: -1}, # SW
  {x: -1, y: 0},  # W
  {x: -1, y: 1},  # NW
]

# Pre-normalized vectors (1 length) for movement
# magnitude  = ((@x**2)+(@y**2))**0.5
# normalized = {x/magnitude, y/magnitude}
DirectionLookupNormalized = [
  {x: 0, y: 1},                                     # N
  {x: 0.7071067811865474, y: 0.7071067811865474},   # NE
  {x: 1, y: 0},                                     # E
  {x: 0.7071067811865474, y: -0.7071067811865474},  # SE
  {x: 0, y: -1},                                    # S
  {x: -0.7071067811865474, y: -0.7071067811865474}, # SW
  {x: -1, y: 0},                                    # W
  {x: -0.7071067811865474, y: 0.7071067811865474},  # NW
]

# Some vector functions not present in Geometry::
def vec2_subtract a, b
  {x: a.x - b.x, y: a.y - b.y}
end

def vec2_cross a,b
  a.x * b.y - a.y * b.x
end

def vec2_angle_between a,b
  Math.atan2(vec2_cross(a,b), Geometry::vec2_dot_product(a,b))
end

def init_game args
  # todo these should be in the gamestate class...
  args.state.player         = EntityFactory::make_player
  args.state.enemies        = []
  args.state.player_attacks = []
  args.state.world          = WorldGrid.new args, GRID_DIMENSION, CELL_SIZE
  args.state.world.goal_location = PLAYER_START

  args.state.start_time = Kernel.tick_count
  args.state.seconds_survived = 0
  args.state.xp = 0
  args.state.player_level = 1

  # Position player
  ploc = args.state.world.coord_to_cell_center PLAYER_START.x, PLAYER_START.y
  args.state.player.x, args.state.player.y = ploc.x, ploc.y

  # Game logic runner
  args.state.current_state = State_Gameplay.new args

  puts "Initialized"
end

def tick args
  # Initialize/reinitialize
  if !args.state.initialized
    init_game args
    args.state.initialized = true
  end

  # Execute current game state (menu, gameplay or gameover)
  if args.state.current_state
    args.state.current_state.args = args
    args.state.current_state.tick
  end

  # Debug keys
  # Reset
  if args.inputs.keyboard.key_down.r
    $gtk.reset_next_tick
  end

  # Debug stats
  args.outputs.labels << { x: 100.from_right, y: 20.from_top, r: 255, g: 255, b: 255, size_enum: -2, text: "FPS: #{args.gtk.current_framerate.to_sf}" }
end

class Pickup

end

module EntityFactory
  def self.make_player
    {
      x: 0,
      y: 0,
      w: PLAYER_SPRITE_WIDTH,
      h: PLAYER_SPRITE_HEIGHT,
      path: 'sprites/frank.png',
      tile_x: 0,
      tile_y: 0,
      tile_w: PLAYER_SPRITE_WIDTH,
      tile_h: PLAYER_SPRITE_HEIGHT,
      anchor_x: 0.5, anchor_y: 0.5,
      health: PLAYER_HEALTH,
      attack_cooldown_max: PLAYER_ATTACK_COOLDOWN,
      attack_cooldown:     PLAYER_ATTACK_COOLDOWN,
      score:  0
    }
  end

  $villager_style = 0
  $villager_flip  = 0
  def self.make_enemy xpos,ypos
    $villager_style = ($villager_style + 42) % 84
    $villager_flip += 1
    {
      x: xpos,
      y: ypos,
      w: ENEMY_SPRITE_WIDTH,
      h: ENEMY_SPRITE_HEIGHT,
      anchor_x: 0.5,
      anchor_y: 0.5,
      path: 'sprites/villager.png',
      tile_x: 0,
      tile_y: $villager_style,
      tile_w: ENEMY_SPRITE_WIDTH,
      tile_h: ENEMY_SPRITE_HEIGHT,
      flip_horizontally: ($villager_flip % 3) == 0,
      health: 1
    }
  end

  # Punch wave (attached to the player)
  def self.make_player_attack xoffs, yoffs, flip
    #xoffs = flip ? -25 : 25
    {
      x: 0,
      y: 0,
      xoffs: flip ? -xoffs : xoffs,
      yoffs: yoffs,
      anchor_x: flip ? 0.8 : 0.2,
      anchor_y: 0.5,
      flip_horizontally: flip,
      path: 'sprites/player-attacks.png',
      r: 255,
      g: 255,
      b: 255,
      a: 255,
      w: 30,
      h: 50,
      scale: 1.0,
      life:  20,
    }
  end
end # module EntityFactory

# Running the game logic
class State_Gameplay
  attr_gtk

  def initialize args
    self.args = args
  end

  def tick
    args.state.seconds_survived = args.state.start_time.elapsed_time.idiv(60)

    plr_loc = state.world.world_to_coord state.player.x, state.player.y
    args.state.world.goal_location = plr_loc
    args.state.world.tick

    spawn_enemies args
    collide_enemies
    move_enemies_no_overlap
    tick_player args

    # Game over check
    if args.state.player.health <= 0 && Cheats::GODMODE == false
      args.state.current_state = State_Gameover.new args
    end

    args.outputs.background_color = [40,45,35]

    # Render world
    #state.world.render_grid_lines
    #state.world.render_distance_field

    # Render characters
    args.outputs.sprites << [args.state.player, args.state.enemies]
    args.outputs.sprites << state.player_attacks

    debug_render_collision_rects

    render_hud

    # Debug watches
    args.outputs.debug.watch args.state.world.goal_location
    args.outputs.debug.watch args.state.enemies.length.to_i
  end

  def spawn_enemies args
    # Spawn enemies more frequently as the player's score increases.
    if rand < (100+args.state.player[:score])/(10000 + args.state.player[:score]) || Kernel.tick_count.zero?
      theta = rand * Math::PI * 2
      args.state.enemies << EntityFactory::make_enemy(640 + Math.cos(theta) * 300, 360 + Math.sin(theta) * 300)
    end
  end
  
  # Collide enemies with player (they die in 1 hit and damage player)
  def collide_enemies
    # Collide against player
    collisions = state.enemies.find_all { |b| b.intersect_rect? state.player }
    collisions.each do |enemy|
      enemy.health -= 1
      state.player.health -= 1
    end

    # Remove deads (put into a dead list while their death anim plays)
    args.state.enemies.reject! do |enemy|
=begin
      # Check if enemy and player are within X pixels of each other
      if enemy.health > 0 && PLAYER_COLLIDE_RADIUS_SQ > (enemy.x - args.state.player.x) ** 2 + (enemy.y - args.state.player.y) ** 2
        # Enemy is touching player. Kill enemy, and reduce player HP by 1.
        args.state.player.health -= 1
        enemy.health -= 1
      else
        # Player bullet/attack collisions
      end
=end
      if enemy.health <= 0
        give_score SCORE_PER_KILL
        true
      end
    end
  end
  
  # Move enemies towards player. Use the current grid cell's vector
  # to move towards player's location, at close range use more precise
  # Direction towards player.
  def move_enemies args
    args.state.enemies.each do |enemy|
      # Steer towards player
      # Get the angle from the enemy to the player
      #theta   = Math.atan2(enemy.y - args.state.player.y, enemy.x - args.state.player.x)
      # Convert the angle to a vector pointing at the player
      #dx, dy  = theta.to_degrees.vector ENEMY_MOVE_SPEED
      # Move the enemy towards thr player
      #enemy.x -= dx
      #enemy.y -= dy

      # Read direction from the vector field
      current_loc = state.world.world_to_coord enemy.x, enemy.y
      current_idx = state.world.coord_to_index current_loc.x, current_loc.y
      best_dir    = DirectionLookupNormalized[state.world.vector_field[current_idx]]
      enemy.x += best_dir.x * ENEMY_MOVE_SPEED
      enemy.y += best_dir.y * ENEMY_MOVE_SPEED
    end
  end

  def check_enemy_overlap a, b
    pos_diff = {
      x: b.x - a.x,
      y: b.y - a.y
    }
    mag = Geometry::vec2_magnitude pos_diff
    mag <= ENEMY_COLLIDE_RADIUS
  end

  def move_enemies_no_overlap
    state.enemies.each do |enemy|
      # Read direction from the vector field
      current_loc = state.world.world_to_coord enemy.x, enemy.y
      current_idx = state.world.coord_to_index current_loc.x, current_loc.y
      enemy.tile_x = (current_idx % 2 == 0) ? 0 : ENEMY_SPRITE_WIDTH
      move_dir    = DirectionLookupNormalized[state.world.vector_field[current_idx]]

      move_delta = { x: move_dir.x * ENEMY_MOVE_SPEED, y: move_dir.y * ENEMY_MOVE_SPEED}

      # Don't move, if we would overlap others
      move_blocked = false
      state.enemies.each do |other_enemy|
        next if enemy == other_enemy
        break if move_blocked

        # https://www.youtube.com/watch?v=UAlYELsxYfs
        # The enemies overlap, check if we are moving towards or away
        dir_to_other = vec2_subtract({x:other_enemy.x, y:other_enemy.y}, {x:enemy.x, y:enemy.y})
        mag          = Geometry::vec2_magnitude dir_to_other
        # not overlapping (todo merge with above check)
        if mag > 1 && mag < ENEMY_COLLIDE_RADIUS
          normal_to_other = Geometry::vec2_normalize dir_to_other
          angle_between   = (vec2_angle_between normal_to_other, move_dir).abs
          if angle_between < Math::PI / 4.0
            move_blocked = true
          end
        end
      end

      if !move_blocked
        enemy.x += move_dir.x * ENEMY_MOVE_SPEED
        enemy.y += move_dir.y * ENEMY_MOVE_SPEED
      end
    end
  end
  
  def move_player
    if args.inputs.directional_angle
      args.state.player.x += args.inputs.directional_angle.vector_x * PLAYER_MOVE_SPEED
      args.state.player.y += args.inputs.directional_angle.vector_y * PLAYER_MOVE_SPEED
      #enemy.tile_x = (current_idx % 2 == 0) ? 0 : ENEMY_SPRITE_WIDTH
      state.player.anim_time  ||= 0
      state.player.anim_frame ||= 0
      state.player.anim_time += 3
      if state.player.anim_time > 20
        state.player.anim_time  = 0
        state.player.anim_frame = (state.player.anim_frame + 1) % 2
        state.player.tile_x = (state.player.anim_frame) == 0 ? 0 : PLAYER_SPRITE_WIDTH
      end

      if args.inputs.directional_angle.vector_x.abs == 1
        args.outputs.debug.watch args.inputs.directional_angle.vector_x
        state.player.flip_horizontally = args.inputs.directional_angle.vector_x < 0
      end
    end
  end

  def tick_player args
    move_player

    # Attack
    state.player.attack_cooldown -= 1
    if state.player.attack_cooldown <= 0
      state.player.attack_cooldown = state.player.attack_cooldown_max
      state.player_attacks << EntityFactory::make_player_attack(25, 0, state.player.flip_horizontally)
    end

    state.player_attacks.each do |attack|
      attack.x = attack.xoffs + state.player.x
      attack.y = attack.yoffs + state.player.y
      attack.life -= 1
      attack.w += 0.15
      attack.h += 0.2
    end

    Geometry.each_intersect_rect(state.player_attacks, state.enemies) do |attack, enemy|
      attack.g = attack.b = 0
      enemy.health -= 1
    end

    state.player_attacks.reject! {|attack| attack.life <= 0 }
  end

  def render_hud
    minutes = (args.state.seconds_survived / 60) % 60
    seconds = args.state.seconds_survived % 60

    args.outputs.labels << { x: 100.from_right, y: 90.from_top,
      r: 255, g: 255, b: 255, size_enum: -2,
      text: "#{minutes.round.to_s.rjust(2, '0')}:#{seconds.round.to_s.rjust(2, '0')}"
    }

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

  def debug_render_collision_rects
    state.rect_1 = state.player.rect
    outputs.borders << state.player.rect.merge(g: 255)
    outputs.borders << state.enemies
    outputs.borders << state.player.attacks
  end
end

# Player has died or survived long enough (and died)
class State_Gameover
  attr_gtk

  def initialize args
    self.args = args
  end

  def tick
    args.outputs.background_color = [40,10,70]

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

  attr_accessor :goal_location
  attr_reader   :vector_field

  def initialize args, dimension, cell_size
    @args = args
    @width         = dimension
    @height        = dimension
    @cell_size     = cell_size
    @inv_cell_size = 1 / cell_size
    @origin        = { x: 0, y: 0 }

    @cell_half_size     = @cell_size / 2

    @goal_location = { x:0, y:0 }

    # Field storing the distance from the player's location
    @distance_field = Array.new(@width * @height, -1)
    # Field indicating which direction to go from the current cell to
    # Reach the player location fastest. Does not store the actual vector but
    # An index into a lookup table. (Could be packed into the same array as distance field)
    @vector_field = Array.new(@width * @height, 0)

    # Walls
    @cost_field = Array.new(@width * @height, 0)

    set_impassable 10,13
    set_impassable 11,13
    set_impassable 12,13

    set_impassable 20,5
    set_impassable 20,6
    set_impassable 20,7
    set_impassable 21,5
    set_impassable 21,6
    set_impassable 21,7

    set_impassable 2,6
    set_impassable 3,6
    set_impassable 4,6
    set_impassable 5,6
  end

  def set_impassable x,y
    @cost_field[coord_to_index(x,y)] = 1
  end

  def is_impassable? x,y
    @cost_field[coord_to_index(x,y)] > 0
  end

  # Grid x,y location to array index
  def index_to_coord index
    x = index % @width
    y = index.idiv(@width)
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

  def render_distance_field
    return unless @distance_field

    #@distance_field.each_with_index do |distance,idx|
    #  coord  = index_to_coord idx
    #  center = coord_to_cell_center coord.x, coord.y
    #  outputs.labels << { x: center.x, y: center.y, r: 255, g: 255, b: 255, size_enum: 0, text: distance, alignment_enum: 1 }
    #end

    @distance_field.each_with_index do |distance,idx|
      direction = @vector_field[idx]
      dir_vec   = DirectionLookupNormalized[direction]
      coord  = index_to_coord idx
      center = coord_to_cell_center coord.x, coord.y
      if !is_impassable?(coord.x, coord.y)
        outputs.labels << { x: center.x, y: center.y,
          r: 128, g: 128, b: 128,
          size_enum: -4, text: "#{distance}, #{direction}", alignment_enum: 1
        }
        outputs.lines << {
          x: center.x,
          y: center.y,
          w: dir_vec.x * 10,
          h: dir_vec.y * 10,
          r: 120
        }
      end
    end
  end

  # Get the 4 neighbors, unless we're at the edge
  def get_neighbors cell
    neighbors = []

    neighbors << {x: cell.x,     y: cell.y - 1} unless cell.y == 0
    neighbors << {x: cell.x - 1, y: cell.y    } unless cell.x == 0
    neighbors << {x: cell.x,     y: cell.y + 1} unless cell.y == @height - 1
    neighbors << {x: cell.x + 1, y: cell.y    } unless cell.x == @width - 1

    neighbors
  end

  def get_distance_value x, y
    if x > -1 && y > -1 && x < @width && y < @height
      idx = coord_to_index(x, y)
      return 1000 if @distance_field[idx] == -1
      return @distance_field[idx]
    else
      return 1000
    end
  end

  def tick
    return if @prev_location == @goal_location
    @prev_location == @goal_location
    # Todo: Don't calculate this, if the position is the same
    # Split the calculation over multiple frames to reduce the load
    @distance_field.fill(-1)

    # Calculate distances
    start_loc = @goal_location
    start_idx = coord_to_index start_loc.x, start_loc.y
    frontier  = [start_loc]
    @distance_field[start_idx] = 0
    until frontier.empty?
      current = frontier.shift
      get_neighbors(current).each do |neighbor|
        neighbor_idx = coord_to_index neighbor.x, neighbor.y
        if @distance_field[neighbor_idx] == -1 && @cost_field[neighbor_idx] == 0 # not visited
          frontier << neighbor
          current_idx  = coord_to_index current.x, current.y
          @distance_field[neighbor_idx] = 1 + @distance_field[current_idx]
        end
      end
    end

    # Data for looping through neighbors in the following calculation
    # xoffset, yoffset and which direction they correspond to
    DirCheckData = [
      [0, 1, North],
      [1, 0, East],
      [0, -1, South],
      [-1, 0, West],

      [1, 1,   NorthEast],
      [1, -1,  SouthEast],
      [-1, -1, SouthWest],
      [-1, 1,  NorthWest],
    ]

    # Calculate the optimal direction from each cell
    # Look around the neighboring cells and check which has the lowest distance
    # We check all 8 neighbors here to allow diagonal movement
    @distance_field.each_with_index do |distance, idx|
      current_loc    = index_to_coord idx
      best_direction = North
      best_distance  = 10000

      DirCheckData.each do |direction|
        new_distance = get_distance_value(current_loc.x + direction[0], current_loc.y + direction[1])
        if new_distance < best_distance
          best_direction = direction[2]
          best_distance  = new_distance
        end
      end

      @vector_field[idx] = best_direction
    end
  end
end