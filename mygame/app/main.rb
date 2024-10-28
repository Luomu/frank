# Avoid or fight villagers
# Collect bolts to grow stronger
# Survive as long as you can
#
# TODO:
# - Collect electricity to heal
# - Obstacles
# - Perf: refactor sprites to use classes

require 'app/curves.rb'

# Constants
PLAYER_HEALTH     = 16
PLAYER_MOVE_SPEED = 4.5
ENEMY_MOVE_SPEED  = 0.1
ENEMY_DRAG        = 0.75
SCORE_PER_KILL    = 10
XP_PICKUP_VALUE   = 1
MAX_LEVEL = 100

GRID_DIMENSION    = 32
CELL_SIZE         = 40
WORLD_SIZE        = GRID_DIMENSION * CELL_SIZE

MAX_ENEMIES          = 600
ENEMY_RADIUS         = 18 # used for enemy-to-enemy collisions
ENEMY_SPRITE_HEIGHT  = 42
ENEMY_SPRITE_WIDTH   = 32
PLAYER_SPRITE_WIDTH  = 32
PLAYER_SPRITE_HEIGHT = 48
PLAYER_COLLIDE_RADIUS_SQ = 35 * 35

# Weapon balancing data
# Fist attack cooldown, in ticks
Player_Fist_Attack_Cooldown_Curve = Curve.new(:linear,
  [
    [1,   65],
    [10,  45],
    [100, 20],
  ]
)

# Secondary attacks for fist, faster when leveling
Player_Fist_Sub_Attack_Cooldown_Curve = Curve.new(:linear,
  [
    [1,   20],
    [100, 10],
  ]
)

module Cheats
  ENABLED = true
  GODMODE = false
end

$debug_show_grid       = false
$debug_show_collisions = false

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

def round_up number, multiple
  return number if multiple == 0
  remainder = number % multiple
  return number if remainder == 0
  number + multiple - remainder
end

def tick args
  # Initialize/reinitialize
  if !args.state.initialized
    # Game logic runner
    args.state.current_state = State_Gameplay.new args
    # Used to visualize lvl up curves
    #args.state.current_state = State_CurveTest.new args
    args.state.initialized = true
    args.audio[:track_1] = {
      input: "sounds/music-stage1.ogg",
      gain: 0.0,
      looping: true
    }
  end

  if args.audio[:track_1].gain < 1.0
    args.audio[:track_1].gain += 0.001
  end

  # Execute current game state (menu, gameplay or gameover)
  if args.state.current_state
    args.state.current_state.args = args
    args.state.current_state.tick
  end

  # Debug keys
  # Reset
  if Cheats::ENABLED
    if args.inputs.keyboard.key_down.r
      $gtk.reset_next_tick
    end

    if args.inputs.keyboard.key_down.l
      args.state.xp = args.state.next_xp_level
    end

    if args.inputs.keyboard.key_down.p
      $debug_show_grid = !$debug_show_grid
    end
  end

  # Debug stats
  args.outputs.labels << { x: 100.from_right, y: 20.from_top, r: 255, g: 255, b: 255, size_enum: -2, text: "FPS: #{args.gtk.current_framerate.to_sf}" }
end

# Thing that hurts enemies
# Weapon 1: Punches (leveling up increases count and directions)
# Weapon 2: Potion (creates acid that damages enemies and marks an area as obstacle)
class Weapon
  attr_accessor :attack_cooldown
  attr_accessor :attack_cooldown_max

  def initialize
    @attack_cooldown = 0
    @attack_cooldown = 0
  end

  # Increase efficiency on player level up
  def level_up new_level
  end

  def tick args
  end
end

class FrankFist < Weapon
  attr_reader :sub_attack_cooldown_max

  def initialize
    super
    @attack_cooldown         = Player_Fist_Attack_Cooldown_Curve.evaluate(1)
    @attack_cooldown_max     = Player_Fist_Attack_Cooldown_Curve.evaluate(1)
    @num_sub_attacks         = 1
    @curr_sub_attack         = 0
    @sub_attack_cooldown_max = Player_Fist_Sub_Attack_Cooldown_Curve.evaluate(1)
    @player_side_on_start    = false # keeps the attack pattern predictable if changing facing mid-attack
  end

  def level_up new_level
    @attack_cooldown_max     = Player_Fist_Attack_Cooldown_Curve.evaluate(new_level)
    @sub_attack_cooldown_max = Player_Fist_Sub_Attack_Cooldown_Curve.evaluate(new_level)

    case new_level
    when 1..2
      @num_sub_attacks = 1
    when 3..4
      @num_sub_attacks = 2
    when 5..6
      @num_sub_attacks = 3
    else
      @num_sub_attacks = 4
    end
  end

  def tick args
    state = args.state
    @attack_cooldown -= 1
    if @attack_cooldown <= 0
      @curr_sub_attack += 1

      case @curr_sub_attack
      when 1 # right!
        @player_side_on_start = state.player.flip_horizontally
        state.player_attacks << EntityFactory::make_player_attack(25, 0, @player_side_on_start)
      when 2 # left!
        state.player_attacks << EntityFactory::make_player_attack(25, 0, !@player_side_on_start)
      when 3 # left up!
        state.player_attacks << EntityFactory::make_player_attack(15, 15, @player_side_on_start)
      when 4 # right up!
        state.player_attacks << EntityFactory::make_player_attack(15, 15, !@player_side_on_start)
      end

      if @curr_sub_attack >= @num_sub_attacks # reset sequence
        @attack_cooldown = @attack_cooldown_max
        @curr_sub_attack = 0
      else # queue next atk in sequence
        @attack_cooldown = @sub_attack_cooldown_max
      end
    end
  end
end

# Flies in parabolic arc
# Creates a zone of acid on ground, that enemies avoid
class AcidFlask < Weapon
  def initialize
    @attack_cooldown     = 50
    @attack_cooldown_max = @attack_cooldown
    @projectiles = []
    @acid_pools  = []
    @side = 1
  end

  def tick args
    @attack_cooldown -= 1
    if @attack_cooldown <= 0
      # Spawn ye flask that flies in a curved arc
      target_cell = args.state.world.get_random_cell_on_screen
      target_loc  = args.state.world.coord_to_cell_center target_cell.x, target_cell.y
      start_x = args.state.player.x
      @side   = @side > 0 ? -1 : 1
      end_x   = target_loc.x
      start_y = args.state.player.y + 60
      end_y   = target_loc.y

      mid_x = (start_x + end_x) / 2
      mid_y = ((start_y + end_y) / 2) + 220
      
      projectile = AcidFlaskProjectile.new(start_x, start_y)
      projectile.life = 100
      projectile.curve = {
        x: Curve.new(:ease_out_sine,
        [
          [0.0, start_x],
          #[0.5, mid_x],
          [1.0, end_x],
        ]),
        y: Curve.new(:ease_in_sine,
        [
          [0.0,  start_y],
          [0.5,  mid_y],
          [1.0,  end_y],
        ])
      }
      args.state.fx << projectile # Using FX array to render as these don't interact and will appear on top
      @projectiles  << projectile # Array for local logic
      @attack_cooldown = @attack_cooldown_max
    end

    world = args.state.world
    @projectiles.each do |flask|
      flask.life -= 1
      time = 1.0 - (flask.life / 100.0)
      new_x = flask.curve.x.evaluate(time)
      new_y = flask.curve.y.evaluate(time)
      flask.x = new_x
      flask.y = new_y

      if flask.is_finished?
        flask_loc = world.world_to_coord flask.x, flask.y
        # Mark location impassable (may already have an obstacle)
        world.cost_field[world.coord_to_index(flask_loc.x,flask_loc.y)] += 2

        # Spawn acid pool/cloud/whatever
        cell_center = world.coord_to_cell_center flask_loc.x, flask_loc.y
        acid_pool = EntityFactory::make_fx_acid_pool(cell_center.x, cell_center.y, flask_loc)
        args.state.fx << acid_pool # for rendering
        @acid_pools << acid_pool
      end
    end
    @projectiles.reject! {|flask| flask.is_finished?}

    # Update acid pools
    @acid_pools.each do |pool|
      pool.life -= 1
      if pool.is_finished?
        # Free up location
        world.cost_field[world.coord_to_index(pool.location.x, pool.location.y)] -= 2
      end
    end
    @acid_pools.reject! {|pool| pool.is_finished?}
  end
end

# Angry villager
class Enemy
  attr_sprite
  attr_accessor :health
  attr_accessor :prev_x
  attr_accessor :prev_y
  attr_reader   :radius

  def initialize xpos, ypos, villager_style, flip
    @x      = xpos
    @y      = ypos
    @prev_x = xpos
    @prev_y = ypos
    @radius = ENEMY_RADIUS
    @w = ENEMY_SPRITE_WIDTH
    @h = ENEMY_SPRITE_HEIGHT
    @anchor_x = 0.5
    @anchor_y = 0.5
    @path = 'sprites/villager.png'
    @tile_x = 0
    @tile_y = villager_style
    @tile_w = ENEMY_SPRITE_WIDTH
    @tile_h = ENEMY_SPRITE_HEIGHT
    @flip_horizontally = flip
    @health = 1
    @a = 255

  end

  def start_death
    @r = 255
    @g = 0
    @b = 0
    @a = 255
  end
end

# Healing or level up pickup
class Pickup
  attr_sprite
  attr_reader :activated

  def initialize x, y, tile_xoffs
    @x = x
    @y = y
    @w = 32
    @h = 32
    @anchor_x = 0.5
    @anchor_y = 0.5
    @tile_w = 32
    @tile_h = 32
    @path   = 'sprites/pickups.png'
    @tile_x = tile_xoffs

    @activated = false
  end

  def pick_up state
    @activated = true
  end
end

class ExperiencePickup < Pickup
  def initialize x, y
    super x,y,0
  end

  def pick_up state
    super state
    state.xp += XP_PICKUP_VALUE
  end
end

class HealthPickup < Pickup
  def initialize x,y
    super x,y,32
  end

  def pick_up state
    super state
    state.player.health = state.player.health_max
    state.fx << EntityFactory::make_fx_heal(state.player.x, state.player.y)
  end
end

class Effect
  attr_sprite
  attr_accessor :life

  def initialize x,y
    @x    = x
    @y    = y
  end

  def tick
    @life -= 1
  end

  def is_finished?
    @life < 0
  end
end

 # "LEVEL UP" text
class LevelUpEffect < Effect
  def initialize x,y
    super x,y
    @life = 20
    @anchor_x = 0.5
    @anchor_y = 0.5
    @path = 'sprites/text-level-up.png'
    @a = 255
    @w = 103
    @h = 33
  end

  def tick
    super
    @a = (@a - 10).greater(0)
    @y += 1
  end
end

# "LIFE UP" text or heart icon
class HealEffect < Effect
  def initialize x,y
    super x,y
    @life = 20
    @anchor_x = 0.5
    @anchor_y = 0.5
    @a = 255
    @w = 32
    @h = 32
    @path   = 'sprites/pickups.png'
    @tile_x = 32
    @tile_y = 0
    @tile_w = 32
    @tile_h = 32
  end

  def tick
    super
    @a = (@a - 5).greater(0)
    @w += 2
    @h += 2
  end
end

class AcidFlaskProjectile < Effect
  attr_accessor :curve
  def initialize x,y
    super x,y
    @life = 20
    @anchor_x = 0.5
    @anchor_y = 0.5
    @path = 'sprites/pickups.png'
    @a = 255
    @w = 32
    @h = 32
    @tile_x = 32
    @tile_w = 32
    @tile_h = 32
    @curve  = nil # set by AcidFlask
  end

  def tick
    # Managed by the weapon class
  end
end # AcidFlaskProjectile

# Damaging area that temporarily affects enemy movement
class AcidPool < Effect
  attr_reader :location

  def initialize x,y,location
    super x,y
    @life = 28.seconds
    @anchor_x = 0.5
    @anchor_y = 0.5
    @path = 'sprites/acid-cloud.png'
    @a = 255
    @w = CELL_SIZE
    @h = CELL_SIZE
    @tile_x = 0
    @tile_y = 0
    @tile_w = 32
    @tile_h = 32
    @location = location
    @anim_frame
  end

  AcidFrames = [0, 32, 64]
  def tick
    # Again, we let the weapon control the lifetime of this item (keeps logic in one place)
    # Presentation here
    frame_index = 0.frame_index 3, 20, true
    @tile_x = AcidFrames[frame_index]
  end
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
      health:     PLAYER_HEALTH,
      health_max: PLAYER_HEALTH,
    }
  end

  $villager_style = 0
  $villager_flip  = 0
  def self.make_enemy xpos,ypos
    $villager_style = ($villager_style + 42) % 84
    $villager_flip += 1
    Enemy.new(xpos, ypos, $villager_style, ($villager_flip % 3) == 0)
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

  def self.make_xp_pickup xpos, ypos
    ExperiencePickup.new(xpos, ypos)
  end

  def self.make_health_pickup xpos, ypos
    HealthPickup.new(xpos, ypos)
  end

  def self.make_fx_level_up xpos, ypos
    LevelUpEffect.new(xpos, ypos)
  end

  def self.make_fx_heal xpos, ypos
    HealEffect.new(xpos, ypos)
  end

  def self.make_fx_acid_pool xpos, ypos, location
    AcidPool.new(xpos, ypos, location)
  end
end # module EntityFactory

# Running the game logic
class State_Gameplay
  attr_gtk
  attr_accessor :pickups

  def initialize args
    self.args = args
    state.player         = EntityFactory::make_player
    state.enemies        = []
    state.player_attacks = []
    state.fx             = []
    state.pickups        = []
    state.dead_enemies   = []
    state.world          = WorldGrid.new args, GRID_DIMENSION, CELL_SIZE
    state.world.goal_location = PLAYER_START
    state.start_time     = Kernel.tick_count
    state.seconds_survived = 0
    state.xp             = 0
    state.player_level   = 1
    state.score          = 0
    state.xp             = 0
    state.next_xp_level  = player_get_next_xp_level state.player_level
    state.player_weapons = [ FrankFist.new, AcidFlask.new ]

    # Position player
    ploc = state.world.coord_to_cell_center PLAYER_START.x, PLAYER_START.y
    state.player.x, state.player.y = ploc.x, ploc.y
  end

  def tick
    args.state.seconds_survived = args.state.start_time.elapsed_time.idiv(60)

    plr_loc = state.world.world_to_coord state.player.x, state.player.y
    args.state.world.goal_location = plr_loc
    args.state.world.tick

    tick_enemies
    tick_player
    tick_pickups
    tick_fx

    # Game over check
    if args.state.player.health <= 0 && Cheats::GODMODE == false
      args.state.current_state = State_Gameover.new args
    end

    args.outputs.background_color = [40,45,35]

    # Render world
    #state.world.render_grid_lines
    state.world.render_distance_field if $debug_show_grid

    # Render characters
    args.outputs.sprites << [state.pickups, state.dead_enemies, state.enemies, state.player]
    args.outputs.sprites << [state.fx, state.player_attacks]

    debug_render_collision_rects if $debug_show_collisions

    render_hud

    # Debug watches
    outputs.debug << "Enemies #{args.state.enemies.length.to_i}"
    outputs.debug << "HP #{state.player.health.to_i}"
    outputs.debug << "Pickups #{state.pickups.length.to_i}"
    outputs.debug << "Attack #{state.player_weapons[0].attack_cooldown_max.to_i} #{state.player_weapons[0].sub_attack_cooldown_max.to_i}"
  end

  def player_get_next_xp_level current_level
    next_level = current_level + 1
    if next_level < MAX_LEVEL
      round_up((next_level**2 / 0.5).floor, 10)
    else
      0
    end
  end

  def player_level_up state
    state.player_level += 1
    state.xp -= state.xp
    state.next_xp_level = player_get_next_xp_level state.player_level

    # Improve weapons
    state.player_weapons.each { |w| w.level_up state.player_level }

    # Level up fx
    state.fx << EntityFactory::make_fx_level_up(state.player.x, state.player.y + 60)
  end

  def spawn_enemies
    # Spawn enemies more frequently as the player's score increases.
    return if state.enemies.length > MAX_ENEMIES
    if rand < (100+args.state.score)/(10000 + state.score) || Kernel.tick_count.zero?
      theta = rand * Math::PI * 2
      state.enemies << EntityFactory::make_enemy(640 + Math.cos(theta) * 800, 360 + Math.sin(theta) * 500)
    end
  end

  # XP, health or nothing
  def spawn_pickup enemy
    if (state.player.health / state.player.health_max) < 0.9
      state.pickups << EntityFactory.make_health_pickup(enemy.x,enemy.y)
    else
      state.pickups << EntityFactory.make_xp_pickup(enemy.x,enemy.y)
    end
  end
  
  # Collide enemies with player (they die in 1 hit and damage player)
  def collide_enemies
    player_hitbox = { x: state.player.x, y: state.player.y, w: 12, h: 18, r: 30, g: 255, b: 30, a: 255, anchor_x: 0.5, anchor_y: 0.5}
    #args.outputs.borders << player_hitbox

    # Collide against player
    collisions = state.enemies.find_all { |b| b.intersect_rect? player_hitbox }
    collisions.each do |enemy|
      enemy.health -= 1
      state.player.health -= 1
    end

    # Remove deads (put into a dead list while their death anim plays)
    args.state.enemies.reject! do |enemy|
      if enemy.health <= 0
        give_score SCORE_PER_KILL
        spawn_pickup enemy
        enemy.start_death
        state.dead_enemies << enemy
        true
      end
    end
  end

  # Used to bounce enemies off walls
  # Copy of the enemy to enemy collision code
  def deflect_enemy_from_point enemy, point, dt
    o_1_center_x = enemy.x
    o_1_center_y = enemy.y
    o_2_center_x = point.x
    o_2_center_y = point.y

    o_2_radius = 24

    distance_x = o_1_center_x - o_2_center_x
    distance_y = o_1_center_y - o_2_center_y
    distance = Math.sqrt(distance_x * distance_x + distance_y * distance_y)

    if distance < enemy.radius + o_2_radius
      v_x = (o_2_center_x - o_1_center_x) / distance
      v_y = (o_2_center_y - o_1_center_y) / distance
      delta = enemy.radius + o_2_radius - distance

      o_1_dx = -0.75 * dt * delta * v_x * 0.5
      o_1_dy = -0.75 * dt * delta * v_y * 0.5
      enemy.x += o_1_dx
      enemy.y += o_1_dy
    end
  end

  def move_enemies
    dt = 0.5
    state.enemies.each do |enemy|
      # Read direction from the vector field
      current_loc = state.world.world_to_coord enemy.x, enemy.y
      current_idx = state.world.coord_to_index current_loc.x, current_loc.y
      enemy.tile_x = (current_idx % 2 == 0) ? 0 : ENEMY_SPRITE_WIDTH # 2 frame animation
      move_dir    = DirectionLookupNormalized[state.world.vector_field[current_idx]]

      # Inside obstacles? Deflect away
      if state.world.cost_field[current_idx] > 0
        cell_center = state.world.coord_to_cell_center current_loc.x, current_loc.y
        deflect_enemy_from_point enemy, cell_center, dt
        # Damage from damage zones (shouldn't do here but running out of time :)
        if state.world.cost_field[current_idx] > 1
          enemy.health -= 1
        end
      # Check if the enemy should steer directly towards the player (at 0 distance, or outside play area)
      elsif state.world.outside_world? current_loc
        dir_steer = true
      elsif state.world.distance_field[current_idx] <= 0
        dir_steer = true
      end

      # Get the angle from the enemy to the player
      if dir_steer
        theta   = Math.atan2(enemy.y - args.state.player.y, enemy.x - args.state.player.x)
        # Convert the angle to a vector pointing at the player
        move_dir  = theta.to_degrees.to_vector
        move_dir.x = -move_dir.x
        move_dir.y = -move_dir.y
      end

      acceleration_x = move_dir.x * ENEMY_MOVE_SPEED
      acceleration_y = move_dir.y * ENEMY_MOVE_SPEED

      dx = enemy.x - enemy.prev_x
      dy = enemy.y - enemy.prev_y
      dx += acceleration_x * dt
      dy += acceleration_y * dt
      dx *= ENEMY_DRAG ** dt
      dy *= ENEMY_DRAG ** dt

      enemy.prev_x = enemy.x
      enemy.prev_y = enemy.y
      enemy.x += dx
      enemy.y += dy
    end

    # Enemy to Enemy collisions
    # Deflect overlapping enemies away from each other
    Geometry.each_intersect_rect(state.enemies, state.enemies) do |o_1, o_2|
      o_1_center_x = o_1.x
      o_1_center_y = o_1.y
      o_2_center_x = o_2.x
      o_2_center_y = o_2.y

      distance_x = o_1_center_x - o_2_center_x
      distance_y = o_1_center_y - o_2_center_y
      distance = Math.sqrt(distance_x * distance_x + distance_y * distance_y)

      if distance < o_1.radius + o_2.radius
        v_x = (o_2_center_x - o_1_center_x) / distance
        v_y = (o_2_center_y - o_1_center_y) / distance
        delta = o_1.radius + o_2.radius - distance

        o_1_dx = -0.75 * dt * delta * v_x * 0.5
        o_1_dy = -0.75 * dt * delta * v_y * 0.5
        o_1.x += o_1_dx
        o_1.y += o_1_dy

        o_2_dx = 0.75 * dt * delta * v_x * 0.5
        o_2_dy = 0.75 * dt * delta * v_y * 0.5
        o_2.x += o_2_dx
        o_2.y += o_2_dy
      end
    end
  end

  def tick_enemies
    spawn_enemies
    collide_enemies
    move_enemies

    # Update death anim
    state.dead_enemies.each { |enemy| enemy.a -= 5 }
    state.dead_enemies.reject! {|enemy| enemy.a <= 0 }
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
        state.player.flip_horizontally = args.inputs.directional_angle.vector_x < 0
      end
    end
  end

  def tick_player
    move_player

    # Attack
    state.player_weapons.each do |wpn|
      wpn.tick args
    end

    # Update attack fx
    # todo move inside fist weapon
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

    # Leveling up
    if state.next_xp_level > 0 && state.xp >= state.next_xp_level
      player_level_up state
    end
  end

  def tick_pickups
    collisions = Geometry.find_all_intersect_rect args.state.player, args.state.pickups
    collisions.each do |pickup|
      pickup.pick_up args.state
    end

    # Collide pickups
    # Animate pickups upon collect
    # Reject removed pickups
    state.pickups.reject! {|pickup| pickup.activated }
  end

  def tick_fx
    state.fx.each do |effect|
      effect.tick
    end

    state.fx.reject! {|effect| effect.is_finished?}
  end

  def render_hud
    # Time survived
    minutes = (args.state.seconds_survived / 60) % 60
    seconds = args.state.seconds_survived % 60
    args.outputs.labels << { x: 640, y: 60.from_top,
      r: 255, g: 255, b: 255, size_enum: 2,
      alignment_enum: 1,
      text: "#{minutes.round.to_s.rjust(2, '0')}:#{seconds.round.to_s.rjust(2, '0')}"
    }

    # Health bar under the player
    hp_bar_pos_x = state.player.x + 15
    hp_bar_pos_y = state.player.y - 30
    hp_bar_fill  = (state.player.health / state.player.health_max).clamp(0,1)
    args.outputs.primitives << { x: hp_bar_pos_x, y: hp_bar_pos_y, w: 30, h: 5, anchor_x: 1.0, anchor_y: 1 }.solid!
    args.outputs.primitives << { x: hp_bar_pos_x, y: hp_bar_pos_y, w: hp_bar_fill * 30, h: 5, r: 255, anchor_x: 1.0, anchor_y: 1 }.solid!

    # Experience bar at the top of the screen
    xp        = state.xp
    xp_to_lvl = state.next_xp_level
    level     = state.player_level
    xp_bar_pos_x = 180
    xp_bar_pos_y = 30.from_top
    xp_bar_fill  = (xp/xp_to_lvl).clamp(0,1)
    xp_bar_w     = 920
    args.outputs.primitives << { x: xp_bar_pos_x-1, y: xp_bar_pos_y+1, w: xp_bar_w+2, h: 22, anchor_x: 0.0, anchor_y: 1 }.solid!
    args.outputs.primitives << { x: xp_bar_pos_x, y: xp_bar_pos_y, w: xp_bar_w * xp_bar_fill, h: 20, b: 120, anchor_x: 0.0, anchor_y: 1 }.solid!
    args.outputs.labels << { x: 640, y: 34.from_top,
      r: 255, g: 255, b: 255, size_enum: -4,
      alignment_enum: 1,
      text: "LVL #{level} (#{xp}/#{xp_to_lvl})"
    }
  
    # Score (gold)
    args.outputs.labels << { x: 100, y: 90.from_top,
      r: 255, g: 255, b: 255, size_enum: -2,
      text: "Score: #{args.state.score}"
    }
  end
  
  def give_score amount
    state.score += amount
  end

  def debug_render_collision_rects
    state.rect_1 = state.player.rect
    outputs.borders << state.player.rect.merge(g: 255)
    outputs.borders << state.enemies
    outputs.borders << state.player_attacks
    outputs.borders << state.pickups
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

    minutes = ((args.state.seconds_survived / 60) % 60).to_i
    seconds = (args.state.seconds_survived % 60).to_i
    outputs.labels << { x: 640, y: 200.from_top,
      r: 255, g: 255, b: 49, size_enum: 3,
      alignment_enum: 1,
      text: "GAME OVER, YOU SURVIVED #{minutes}m #{seconds}s"
    }
    outputs.labels << { x: 640, y: 240.from_top,
      r: 255, g: 255, b: 49, size_enum: 1,
      alignment_enum: 1,
      text: "HIT R TO RESTART"
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
  attr_reader   :distance_field
  attr_reader   :cost_field

  def initialize args, dimension, cell_size
    @args = args
    @width         = dimension
    @height        = dimension
    @cell_size     = cell_size
    @inv_cell_size = 1 / cell_size
    @origin        = { x: 0, y: 0 }

    @cell_half_size = @cell_size / 2

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

  def outside_world? loc
    loc.x < 0 || loc.y < 0 || loc.x >= @width || loc.y >= @height
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

  def get_random_cell
    {
      x: rand(@width),
      y: rand(@height)
    }
  end

  def get_random_cell_on_screen
    {
      x: rand(32),
      y: rand(18)
    }
  end

  def tick
    # Todo add dirty flag
    #return if (@prev_location == @goal_location)
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

# Debug visualization of level up curves
class State_CurveTest
  attr_gtk

  def initialize args
    self.args = args
  end

  def tick
    draw_curve args, Player_Fist_Attack_Cooldown_Curve, 10, 10, [128, 43, 67]
  end

  # Evaluate the curve and draw it
  def draw_curve args, curve, x_offs, y_offs, color
    NumPoints = 10
    Size      = 300
    pts = []
    s = curve.start_time
    e = curve.end_time
    incr = (e - s) / NumPoints
    time = s
    y_scale = Size / curve.calculate_max
    x_scale = Size / (NumPoints * incr)
    (0..NumPoints).each do |i|
      time = i * incr
      pts << [
        time * x_scale + x_offs,
        curve.evaluate(time) * y_scale + y_offs
      ]
    end

    #Rendering.set_color COLOR_LAVENDER_P8
    #Rendering.rectangle(x_offs-2,y_offs-2,Size+4,Size+4)
    render_line_strip(pts, color)
  end

  # Render a continuous line from an array of points [[x,y],[x,y]...]
  def render_line_strip point_array, draw_color
      return if !point_array.is_a? Array || point_array.length < 2

      (1..point_array.length-1).each do |idx|
        e_x = point_array[idx][0]
        e_y = point_array[idx][1]
        s_x = point_array[idx-1][0]
        s_y = point_array[idx-1][1]
        $gtk.args.outputs.lines << [s_x, s_y, e_x, e_y, *draw_color]
      end
    end
end