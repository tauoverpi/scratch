def example():
    for i in range(10):
        yield i

print(set(example()))
