import dis

x = list(str(k) for k in range(0, 1000))

def forloop():
    for i in range(0, len(x)):
        x[i] = x[i].strip()

def genloop():
    x = [item.strip() for item in x]

dis.dis(forloop)
print("----")
dis.dis(genloop)

