import dis

def test():
    with open("yieldfile.py") as fd:
        for line in fd:
            yield line

dis.dis(test)
