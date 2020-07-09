class example:
    def __init__(self, initial, limit):
        self.state = initial
        self.limit = limit

    def __iter__(self):
        return self

    def __next__(self):
        if self.state >= self.limit:
            raise StopIteration
        result = self.state
        self.state += 1
        return result

#for thing in example(0, 10):
#    print(thing)

step = example(0, 10).__iter__()
print(step.__next__())
print(step.__next__())

a = (example(0, 10))
print(a)
