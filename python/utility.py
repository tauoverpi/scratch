import math
import random
from typing import List, Any, Dict, Union

random.seed(0xcafebabedeadbeef) # ensure reproducible results

# ---- infinite axis utility system -----

# The framework which you'll only need to write once

class Context:
    """
    Context in which the consideration is being evaluated in.
    At present this consists of the characters.
    """
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
        mod: float = 1 - (1 / len(self.considerations))
        total: float = self.maximum

        for c in self.considerations:
            if total < limit:
                return 0
            result: float = c.score(context)
            total *= clamp(result + (1 - result) * result * mod, 0, 1)
        return total

class Category:
    maximum: float = 1
    considerations: List[Consideration]
    name: str

    def __init__(self, name: str, cons: List[Consideration]):
        self.name = name
        self.considerations = cons

    def score(self, context: Context, limit: float) -> float:
        mod = 1 - (1 / len(self.considerations))
        total = self.maximum # type: float

        for c in self.considerations:
            if total < limit:
                return 0
            result: float = c.score(context)
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
        x: float = other.x - self.x
        y: float = other.y - self.y
        return math.sqrt(x * x + y * y)

class Score:
    score: float
    index: int

    def __init__(self, score, index):
        self.score = score
        self.index = index

class Character:
    position: Point
    health: float = 100
    max_health: float = 100
    categories: List[Category]
    action_sets: Dict[str, List[Action]]


    def __init__(self, init):
        self.position = init["position"]
        self.categories = init["categories"]
        self.action_sets = init["action_sets"]

    def act(self, them):
        # For single utility, treat the "category" as the action
        # list and return the best entry.

        sets = self.score(self.categories, them, True)
        best_category = self.categories[sets[0].index].name
        print("selecting actions from category", best_category)

        # Dual utility allows the programmer to control which actions
        # are available after evaluating the situation the character
        # is in thus providing greater creative control.
        #
        # e.g a character should never execute a wave emote during
        #     combat, with regular utility that can happen if weighted
        #     selection is in use or the emote isn't weighed down by
        #     threat measurement. Dual utility solves this as emotes
        #     won't be considered in combat situations.

        category = self.action_sets[best_category]
        actions = self.score(category, them, False)

        # -- weighted selection --

        # figure out the total
        top = 0
        for a in actions:
            top += a.score

        # pick a value at random within the range
        chosen = random.random() * top
        total = 0

        # find the action score which causes the total to equal or exceed
        # the chosen value
        for a in actions:
            total += abs(a.score)
            if total >= chosen:
                return category[a.index]

        assert False # unreachable

    def score(self, actions: Union[List[Action], List[Category]], them, limited: bool):
        scores: List[Score]= []
        limit: float = 0 # allow all, can be used to cull low value actions
        index: int = 0
        if limited:
            for action in actions:
                result = action.score(Context(self, them), limit)
                if result > limit: limit = result
                print("{} confidence: {:.2f}".format(action.name, result))
                scores += [Score(result, index)]
                index += 1
        else:
            for action in actions:
                result = action.score(Context(self, them), limit)
                print("{} confidence: {:.2f}".format(action.name, result))
                scores += [Score(result, index)]
                index += 1

        return sorted(scores, key=lambda x: -x.score)

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

class ConDistanceAway(Consideration):
    """
    Confidence is tied to the distance from the character's target
    where the further away the target is; the more interesting they
    become.
    """
    max_distance: float

    def __init__(self, distance):
        self.max_distance = distance

    def score(self, context) -> float:
        dist = context.my.position.distanceTo(context.their.position)
        dist = clamp(dist, 0, self.max_distance)
        return dist / self.max_distance


class ConWeak(Consideration):
    """
    Confidence is high when enemy health is low.
    Here we clamp so it doesn't fall too low.
    """
    def score(self, context) -> float:
        return clamp((context.their.max_health - context.their.health) / context.their.max_health, 0.3, 1)

class ConStrong(Consideration):
    """
    Confidence is high when enemy health is high.
    Here we clamp so it doesn't fall too low.
    """
    def score(self, context) -> float:
        return clamp(context.their.health / context.their.max_health, 0.3, 1)

# ---- Actions ----

# Now that we have a list of things a character can consider it's time to define
# things a character can do. Here we define two actions, attack and flee, which
# have the opposite behaviour. As the enemy gets weaker the player gets more
# aggressive and as the distance increases the desire to perform either falls
# as the target is likely too far away.

class ActSwordAttack(Action):
    def __init__(self):
        super().__init__("SwordAttack", [
            ConDistance(5)
        ])

class ActArrowAttack(Action):
    def __init__(self):
        super().__init__("ArrowAttack", [
            ConDistanceAway(20)
        ])

class ActRun(Action):
    def __init__(self):
        super().__init__("Run", [
            ConDistance(5)
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

# ---- Categories ----

# Before selecting an action however we need to select a category (action set)
# to evaluate actions from. Separating actions into categories gives more control
# over which actions can be chosen given the current sitation to avoid characters
# picking really dumb actions to execute.

class CatFlee(Action):
    """
    Flee when damaged, close, and the enemy is strong
    """

    def __init__(self):
        super().__init__("Flee", [
            ConDamage(),     # the desire to flee increases as damage increases
            ConDistance(20), # the desire to flee decreases with distance
            ConStrong()      # the desire to flee is higher when the enemy is healthy
        ])

class CatAttack(Action):
    """
    Attack when healthy, close, and the enemy is weak
    """

    def __init__(self):
        super().__init__("Attack", [
            ConHealth(),     # the desire to attack increases as health increases
            ConDistance(20), # the desire to attack increases the closer the enemy is
            ConWeak()        # the desire to attack increases as the enemy becomes weaker
        ])

# ---- Game ----

player = Character({
    "position": Point(2, 5),
    "categories": [ CatAttack(), CatFlee() ],
    "action_sets": {
        "Attack": [
            ActSwordAttack(),
            ActArrowAttack()
        ],
        "Flee": [
            ActArrowAttack(),
            ActRun()
        ],
    }
})

foe = Character({
    "position": Point(5, 5),
    "categories": [ CatAttack(), CatFlee() ],
    "action_sets": {
        "Attack": [
            ActSwordAttack(),
            ActArrowAttack()
        ],
        "Flee": [
            ActArrowAttack(),
            ActRun()
        ],
    }
})

print("player", player.act(foe).name, "<-- both are equal here")
print("foe",    foe.act(player).name, "<-- same behaviour, same status, same attack")
foe.health = 30
player.health = 50
print("player", player.act(foe).name, "<-- confident that the enemy will be defeated")
print("foe",    foe.act(player).name, "<-- injured, too close, has had enough and is now on the run")
player.position.x = 0
player.position.y = 0
foe.position.y = 13
print("player", player.act(foe).name, "<-- too far to attack with a sword")
print("foe",    foe.act(player).name, "<-- assumes it's safe to attack from a distance")

