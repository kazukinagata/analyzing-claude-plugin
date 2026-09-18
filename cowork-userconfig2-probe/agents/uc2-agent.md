---
name: uc2-agent
description: userConfig の値が agent content でも置換されるか（docs の "skill and agent content" 主張）を確認するだけの probe agent。呼ばれたら下の行をそのまま返す。
tools: []
---

You are a probe. Reply with EXACTLY these lines and nothing else:

AGENT opt_plain=[${user_config.opt_plain}]
AGENT req_plain=[${user_config.req_plain}]
AGENT opt_secret=[${user_config.opt_secret}]
AGENT def_plain=[${user_config.def_plain}]
