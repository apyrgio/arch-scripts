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

    # Check this here since the `in' operator matches the empty parentheses
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
    unit = ""

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
        #print "Calculating %s" % (self.name)

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
            elif dep.name == "co":
                expr = "%d * %d %s %s" % (dep_val, os_val, self.sep, self.val)
            else:
                expr = "%d %s %s" % (dep_val, self.sep, self.val)

            self.val = int(eval(expr))
            self.val = toSize(self.val)
            self.done = 1

        #print "%s is done (%s)" % (self.name, str(self.val))


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

    if s in dependencies:
        return (s, "*", 1)

    return ("", "", s)

# `main' expects the following arguments:
# $1: object size
# $2: block size
# $3: cache objects
# $4: cache size
# $5: bench size
# [$6]: request cap
#
# Arguments $3 to $5 can be in size notation (4096, 4k, 4K; all three equates
# to the same size) or dependent to another. Dependency is defined as
# following:
#                   $arg$op$val     (e.g cs/4, bs*64)
#
# where:
#       $arg is the argument where we depend on. It must either be "co" for
#       cache objects, "cs" for cache size, "bs" for bench size
#       $op is the dendency relationship between the two arguments and must
#       either be "/" for division or "*" for multiplication
#       $val is the constant that is used for the dependency relationship and
#       it must be a number.
#
# Finally argument $6 is an optional one that converts the bench size to
# number of requests if the string is "rc".
def main(argv = None):
    if argv == None:
        argv = sys.argv

    os = argv[1]    # Object size
    bls = argv[2]   # Block size

    for tup in [("co", 3), ("cs", 4), ("bs", 5)]:
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

    #print "Original:\n"
    #pprint(dependencies)

    for key, value in dependencies.iteritems():
        if not value.done:
            value.calculate(os)

    if len(argv) == 7:
        bls = toNumber(bls)
        bs = dependencies["bs"].val
        bs = toNumber(bs)
        bs = bs / bls
        bs = toSize(bs)
        dependencies["bs"].val = bs

    #print "\nFinal:\n"
    #pprint(dependencies)

    print ("%s %s %s" %
            (dependencies["co"].val, dependencies["cs"].val,
                dependencies["bs"].val))
if __name__ == "__main__":
    sys.exit(main())
