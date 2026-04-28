
# Clipboard command EXecution

import os
import sys

end_style_code = "\033[0m"

def formatAsError(text: str):
    text = "\033[91m" + text + end_style_code
    return text

def formatAsSuccess(text: str):
    text = "\033[92m" + text + end_style_code
    return text

getIp = False
getToken = False
commandToExecute = ""

if len(sys.argv) == 3 and sys.argv[1] == "repo":
    if list(repos_dict.keys()).__contains__(sys.argv[2]):
        result = repos_dict[list(repos_dict.keys())[list(repos_dict.keys()).index(sys.argv[2])]]
        getToken = True

elif len(sys.argv) < 2 or len(sys.argv) > 3:
    print(formatAsError(f" | Invalid syntax, please use {sys.argv[0]} <command>"))
    raise SystemExit
else:
    commandToExecute = sys.argv[1]
    if (sys.argv[1]) == "-i":
        commandToExecute = "ip addr | grep 'scope global'"
        getIp = True
    if sys.argv[1].__contains__("hue"):
        commandToExecute = commandToExecute.replace("hue", "python3 /home/iker/.scripts/hue/hue.py")
        print(commandToExecute)

if commandToExecute != "":
    result = os.popen(commandToExecute).read()

if getIp:
    result = ((result.replace("inet ", "")).split("/"))[0].strip()

if result == "":
    print(formatAsError(f" | Command produced no output (") + commandToExecute + formatAsError(")"))
    raise SystemExit
else:
    result = result.strip("\n")
    # os.system(f"echo {result} | xclip -sel clip -r") # wl-copy -n
    os.system(f"echo {result} | wl-copy -n")
    if getIp:
        print(formatAsSuccess(f" | Current IP copied to clipboard (") + result + formatAsSuccess(")"))
    elif getToken:
        print(formatAsSuccess(" | Token for repository ") + sys.argv[2] + formatAsSuccess(" copied to clipboard"))
    else:
        print(formatAsSuccess(f" | Command output copied to clipboard (") + result + formatAsSuccess(")"))
    
    raise SystemExit
