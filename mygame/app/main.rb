# Constants
PLAYER_HEALTH     = 5
PLAYER_MOVE_SPEED = 5
ENEMY_MOVE_SPEED  = 3
SCORE_PER_KILL    = 10

def init args
  args.state.player  = {x: 600, y: 320, w: 80, h: 80, path: 'sprites/circle/white.png', vx: 0, vy: 0, health: PLAYER_HEALTH, cooldown: 0, score: 0}
  args.state.enemies = []
  puts "Initialized"
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