#! /usr/bin/env python

import sys
import re
from pprint import pprint

def toNumber(size):
    match = re.match(r"([0-9]+)([kmg]*)", size, re.I)
    if match:
        tup = match.groups()
        num = int(tup[0])
        unit = tup[1]
    else:
        raise Exception("Invalid unit")

    # Check this here since in `in' operator the '""' is matched
    if unit is "":
        return num

    if unit in "gG":
        num = num * 1024 * 1024 * 1024
    elif unit in "mM":
        num = num * 1024 * 1024
    elif unit in "kK":
        num = num * 1024

    return num


def toSize(num):
    units = ["K", "M", "G"]

    while num >= 1024:
        num = num / 1024
        unit = units.pop(0)

    return str(num) + unit


class Dependency:
    def __repr__(self):
        return "<name: %s, DependsOn: %s, sep: %s, val: %s>" % (self.name,
                self.DependsOn,
                self.sep, self.val)

    def __init__(self):
        self.done = 0

    def calculate(self, os):
        print "Calculating %s" % (self.name)

        if self.done:
            return
        elif not self.DependsOn:
            self.done = 1
        else:
            dep = self.DependsOn
            dep.calculate(os)
            dep_val = toNumber(dep.val)
            os_val = toNumber(os)

            if self.name == "co":
                expr = "%d / %d %s %s" % (dep_val, os_val, self.sep, self.val)
                self.val = eval(expr)
            elif dep.name == "co":
                expr = "%d * %d %s %s" % (dep_val, os_val, self.sep, self.val)
                self.val = eval(expr)
                self.val = toSize(self.val)
            else:
                expr = "%d %s %s" % (dep_val, self.sep, self.val)
                self.val = eval(expr)
                self.val = toSize(self.val)

            self.done = 1

        print "%s is done (%s)" % (self.name, str(self.val))


dependencies = {
        'co': Dependency(),
        'cs': Dependency(),
        'bs': Dependency()
        }


def separate(s):
    for sep in ["/", "*"]:
        sparts = s.partition(sep)
        if sparts[1] != "":
            if not sparts[0] in dependencies:
                raise Exception("Dependency is invalid")
            return sparts

    return ("", "", s)


def main(argv = None):
    if argv == None:
        argv = sys.argv

    os = argv[1]

    for tup in [("co", 2), ("cs", 3), ("bs", 4)]:
        arg = argv[tup[1]]
        sparts = separate(arg)
        dep = dependencies[tup[0]]
        dep.name = tup[0]
        try:
            dep.DependsOn = dependencies[sparts[0]]
        except Exception as e:
            dep.DependsOn = None
        dep.sep = sparts[1]
        dep.val = sparts[2]

    sys.stdout.write("Original:\n")
    pprint(dependencies)

    for key, value in dependencies.iteritems():
        if not value.done:
            value.calculate(os)

    sys.stdout.write("\nFinal:\n")
    pprint(dependencies)


if __name__ == "__main__":
    sys.exit(main())
