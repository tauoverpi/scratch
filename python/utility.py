import math
from typing import List, Any

# ---- utility system -----

# The framework which you'll only need to write once

class Context:
    my: Any
    their: Any

    def __init__(self, me, them):
        self.my = me
        self.their = them

class Consideration:
    """
    A thing for the character to consider, considerations always
    take the current world context and compute a score based on
    what they care about.
    """
    def score(self, context): float

def clamp(x: float, low: float, high: float) -> float:
    if x < low: return low
    if x > high: return high
    return x

class Action:
    """
    Compute the total confidence in this action while giving up
    early if there's another action with a better score.

    A modification factor is defined to lower the penalty of
    having many things to consider as otherwise having many
    considerations with a high score of 0.9 would still make
    the confidence fall faster than actions with few things to
    consider.
    """
    maximum: float = 1
    considerations: List[Consideration]
    name: str

    def __init__(self, name, cons):
        self.name = name
        self.considerations = cons

    def score(self, context, limit: float) -> float:
        mod = 1 - (1 / len(self.considerations)) # type: float
        total = self.maximum # type: float
        for c in self.considerations:
            if total < limit:
                return 0
            result = c.score(context)
            total *= clamp(result + (1 - result) * result * mod, 0, 1)
        return total

# ---- basic stuff ----

# Need data to operate on so we'll define a character and how to measure distance

class Point:
    x: float
    y: float

    def __init__(self, x: float, y: float):
        self.x = x
        self.y = y

    def distanceTo(self, other) -> float:
        x = other.x - self.x
        y = other.y - self.y
        return math.sqrt(x * x + y * y)

class Character:
    position: Point
    health: float = 100
    max_health: float = 100
    actions: List[Action]

    def __init__(self, pos, actions):
        self.position = pos
        self.actions = actions

    def act(self, them):
        scores = []
        limit = 0
        for index, action in enumerate(self.actions):
            result = action.score(Context(self, them), limit)
            print(action.name, "confidence", result)
            scores += [(result, index)]

            if (result > limit): # short circuit
                limit = result

        scores = sorted(scores, key=lambda x: x[0])
        best = scores[len(scores) - 1][1]
        print(self.actions[best].name, "chosen")
        return self.actions[best]

# ---- considerations ----

# From this point on you're defining your framework and data. Now it's on to
# AI programming by converting data into utility scores. Utility scores here
# are values between 1.0 and 0.0 where 1.0 means the character is confident
# while the opposite as they approach 0.0. Note, you can calculate the utility
# easily by dividing the current value by the maximum where the maximum is
# confidence level 1.0. If you want confidence to scale in the other direction
# just invert it `(max - value) / max` such that the more you have the less
# utility it brings.

class ConHealth(Consideration):
    """
    Confidence is tied directly to health where the character has
    a higher confidence the higher their health is.
    """
    def score(self, context) -> float:
        return context.my.health / context.my.max_health

class ConDamage(Consideration):
    """
    Confidence is tied directly to health where the character has
    a lower confidence the higher their health is.
    """
    def score(self, context) -> float:
        return (context.my.max_health - context.my.health) / context.my.max_health

class ConDistance(Consideration):
    """
    Confidence is tied to the distance from the character's target
    where the further away the target is the less interesting they
    become.
    """
    max_distance: float

    def __init__(self, distance):
        self.max_distance = distance

    def score(self, context) -> float:
        dist = context.my.position.distanceTo(context.their.position)
        dist = clamp(dist, 0, self.max_distance)
        return (self.max_distance - dist) / self.max_distance

class ConWeak(Consideration):
    """
    Confidence is high when enemy health is low.
    Here we clamp so it doesn't fall too low.
    """
    def score(self, context) -> float:
        return clamp((context.their.max_health - context.their.health) / context.their.max_health, 0.8, 1)

class ConStrong(Consideration):
    """
    Confidence is high when enemy health is high.
    Here we clamp so it doesn't fall too low.
    """
    def score(self, context) -> float:
        return clamp(context.their.health / context.their.max_health, 0.6, 1)


# ---- Actions ----

# Now that we have a list of things a character can consider it's time to define
# things a character can do. Here we define two actions, attack and flee, which
# have the opposite behaviour. As the enemy gets weaker the player gets more
# aggressive and as the distance increases the desire to perform either falls
# as the target is likely too far away.

class ActFlee(Action):
    """
    Flee when damaged, close, and the enemy is strong
    """

    def __init__(self):
        super().__init__("Flee", [
            ConDamage(),     # the desire to flee increases as damage increases
            ConDistance(20), # the desire to flee decreases with distance
            ConStrong()      # the desire to flee is higher when the enemy is healthy
        ])

class ActAttack(Action):
    """
    Attack when healthy, close, and the enemy is weak
    """

    def __init__(self):
        super().__init__("Attack", [
            ConHealth(),     # the desire to attack increases as health increases
            ConDistance(20), # the desire to attack increases the closer the enemy is
            ConWeak()        # the desire to attack increases as the enemy becomes weaker
        ])

# You can define other actions the same way by just composing a list of things
# which the character should think about before picking the action as they're
# _considering_ their options. This can be called repeatedly as it's pretty fast
# compared to most other AI techniques thus you should be fine running this at
# 200ms to 400ms or so without trouble which is much faster than you can with
# most other systems.

# A thing I didn't include: you can define something called a response curve
# which is a function you apply to the result of every consideration to modify
# how your character reacts and create even more complex behaviours such as a
# troll that may stop fleeing when health is critical and go on a rampage
# instead as you've used a parabolic curve to modify the otherwise linear
# consideration score.
#
#    Response curves              Into something
#    transform this               like this
#
#                                  ,-------------- where the character goes
#                                  v               on a rampage (notice the
#                                                  sharp rise in confidence)
#    |          ,'                |;           ,'
#    |       ,'                   |;         ,'
#   y|    ,'                     y| ;      ,'
#    | ,'                         |  ',  ,'
#    |____________                |______________
#         x                            x
#
#        Health                       Health

# ---- Game ----

player = Character(
    Point(2, 5),
    [ ActFlee(), ActAttack() ],
)

monster = Character(
    Point(5, 5),
    [ ActFlee(), ActAttack() ],
)

print("player", player.act(monster).name)
print("monster", monster.act(player).name)
monster.health = 30
player.health = 50
print("monster", monster.act(player).name)
print("player", player.act(monster).name)

