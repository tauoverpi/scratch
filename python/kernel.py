import queue

# Actor class provides a framework we can inherit from to produce
# valid actors. Any object which follows this model will work in-place
# of this class.
class Actor:
    def __init__(self, pid, init=None):
        self.mailbox = queue.Queue()
        self.pid = pid

# Scheduling of actors consists of the order of sent messages
class Kernel:
    def __init__(self):
        # We store actors in a hashtable so we can quickly update them
        # when they get mail and remove them when they die
        self.store = {}             # Dict[PID, Actor]
        # Scheduling is by message sent where we push the recipient's
        # PID on the queue so they can handle the message
        self.kqueue = queue.Queue() # Queue[PID]
        # Actors need unique addresses so we count up to generate
        # enough
        self.pid_count = 0          # PID

    # Sending looks up the actor and places the message in the actor's mailbox
    def send(self, to, message):
        try:
            print("[kernel] sending to actor at", to, "message:", message)
            self.store[to].mailbox.put(message)
            self.kqueue.put(to)
        except:
            # If the actor is dead we discard the message
            pass

    # A step consists of taking one PID from the kqueue, looking up the actor
    # it refers to and executing that actor's behaviour for the first message
    # in their queue. If kqueue is empty we've reached a starvation state where
    # we can no longer make progress and thus return False to indicate that.
    # Note: Ignore the escape codes for generating pretty colours
    def step(self):
        if not self.kqueue.empty():
            pid = self.kqueue.get()
            escape = "\x1b[38;5;" + str(((pid * 11) % 210) + 16) + "m"
            print(escape, end='')
            try:
                message = self.store[pid].mailbox.get()
                self.store[pid].behaviour(message)
            except Exception as e:
                print(pid, "threw an exception", e)
                self.kill(pid)
                pass
            print("\x1b[0m", end='')
            return True
        else:
            return False

    # Spawning is just placing an actor with a PID in the actor store.
    # No really, there's no more to it...
    def spawn(self, actor, init=None):
        self.pid_count += 1
        self.store[self.pid_count] = actor(self.pid_count, init)
        return self.pid_count

    # Killing an actor removes it from the store. It's much better for
    # supervisors to ping actors to see if they're alive than rely on the kernel
    # checking as the code becomes a pain otherwise.
    def kill(self, pid):
        try:
            self.store.pop(pid)
        except:
            # we don't care if the actor is already dead
            pass
