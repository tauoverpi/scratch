from kernel import *

# This program implements a ring of actors

kernel = Kernel()

# Setup the start and end actor which will quit on the second message
class EndActor(Actor):
    def __init__(self, pid, init):
        super().__init__(pid)
        self.target = False

    def behaviour(self, message):
        if self.target:
            print("[actor] result:", message)
            kernel.kill(self.pid)
        else:
            self.target = True
            kernel.send(message, 1)

# Setup forwarding actors which count by one on each step
class LinkActor(Actor):
    def __init__(self, pid, init):
        super().__init__(pid)
        self.target = init

    def behaviour(self, message):
        kernel.send(self.target, message + 1)
        kernel.kill(self.pid)

# spawn the end actor
end = kernel.spawn(EndActor)
act = end
for _ in range(0, 99):
    # link together all of the link actors
    act = kernel.spawn(LinkActor, init=act)

# send the first message
kernel.send(end, act)

# run to completion
while kernel.step(): pass
