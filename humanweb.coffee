
sys = require 'sys'
xmpp = require 'node-xmpp'
argv = process.argv
http = require 'http'

getRandomInt = (min, max) ->
  return Math.floor(Math.g() * (max - min + 1)) + min;

if argv.length != 4
	 console.error "Usage: <jid> <password> <receiverjid>"
	 process.exit 1

client = new xmpp.Client { jid: argv[2], password: argv[3]  }

Array.prototype.delete = (e) ->
  return if this.indexOf(e) == -1
  this.splice(this.indexOf(e),1)

Array.prototype.random = () ->
  this[getRandomInt(0,this.length - 1)]

Array.prototype.exists = (e) ->
  return this.indexOf(e) >= 0

class Buddylist
  constructor: () ->
    @buddies = {}
    @online = []
    @idle = []

  setOnline: (jid) ->
    return if jid.match(new RegExp('^' + client.jid.user + '@' + client.jid.domain))
    return if !jid.match(new RegExp('/'))
    buddy = @buddies[jid] || {}
    @buddies[jid] = buddy
    buddy.jid = jid
    @online.push jid unless @online.exists jid
    this.setIdle jid
    buddy

  status: (jid) ->
    return 'offline' unless @online.exists jid
    return 'idle' if @idle.exists jid
    return 'serving a request'

  setIdle: (jid) ->
    return jid unless @buddies[jid]
    return jid if @idle.exists jid
    @idle.push(jid)
    jid

  setBusy: (jid) ->
    return jid unless @buddies[jid]
    @idle.delete(jid)
    jid

  setOffline: (jid) ->
    return jid unless @buddies[jid]
    r = new RegExp("^" + jid)
    for e in @online
      if e != undefined and e.match(r)
        @online.delete(e)
        @idle.delete(e)
        @buddies[e] = undefined
    jid

  assignWork: (url, work, fail) ->
    buddy = this.nextIdleBuddy()
    if (buddy)
      buddy.onWorkFinished = work
      this.setBusy(buddy.jid)
      this.sendMessage(buddy.jid, url)

      # In case the user does not respond
      blist = this
      setTimeout ->
        if buddy.onWorkFinished
          blist.setIdle(buddy.jid)
          blist.sendMessage(buddy.jid, "You timed out! Work faster human!")
          fail(504, "The server did not receive a timely response from the upstream human.\n")
      , 90000
    else
      fail(503, "No human available to service your request.\n")

  nextIdleBuddy: () ->
    @buddies[@idle[0]]

  sendMessage: (receiver, message) ->
    console.log "Sending " + message + " to: " + receiver
    e = new xmpp.Element 'message', { to: receiver, type: 'chat' }
    e.c('body').t message
    client.send e

client.buddylist = new Buddylist

client.iq = (query, to = undefined, type = 'get') ->
  attrs = { type: type }
  attrs.to = to if to
  client.send(new xmpp.Element('iq', attrs).cnode(query).tree());

client.getRoster = () ->
  client.iq new xmpp.Element('query', { xmlns: 'jabber:iq:roster' })

client.syncSubscription = (q) ->
  console.log "sync: #{q.jid} #{q.subscription}"
  switch q.subscription
    when 'from'
      console.log 'Subscribing to ' + q.jid
      client.send new xmpp.Element('presence', { to: q.jid, type: 'subscribe' })
    when 'none'
      console.log "User #{q.jid} unsubscribed, leaving on roster"

client.on 'online', () ->
  console.log "Connected to xmpp server"
  e = new xmpp.Element('presence', {})
  e.c('show').t('chat').up().c('status').t('Ask me a question!')
  client.send e
  client.getRoster()

client.on 'stanza', (stanza) ->
  if stanza.is('message') and (stanza.attrs.type == 'chat')
    buddy = client.buddylist.buddies[stanza.attrs.from]
    if buddy == undefined
      console.error 'Received message from unknown buddy ' + stanza.attrs.from
      return

    if buddy.onWorkFinished
      buddy.onWorkFinished(stanza.children[0].children.join(''))
      buddy.onWorkFinished = undefined
    else
      client.buddylist.sendMessage(buddy.jid, 'No web client currently waiting for message')
    client.buddylist.setIdle(buddy.jid)
  if stanza.is('iq')
    console.log "iq: " + stanza
    # roster response
    if stanza.attrs.type == 'result' and stanza.children[0].attrs.xmlns == 'jabber:iq:roster'
      console.log 'Received jabber:iq:roster'
      roster = stanza.children[0]
      roster.children.forEach (item) ->
        if item.attrs.ask == "subscribe"
          client.syncSubscription item.attrs
          return
        if item.attrs.subscription == "from"
          client.syncSubscription item.attrs
          return
      return

    if stanza.attrs.id == "ping"
      console.log "Received ping from #{stanza.attrs.from}, sending pong."
      client.send(new xmpp.Element('iq', { to : stanza.attrs.from, id : 'c2s1', type : 'result' }))
  if stanza.is('presence')
    switch stanza.attrs.type
      when 'subscribe'
        console.log "Subscribe from " + stanza.attrs.from
        client.buddylist.setOnline stanza.attrs.from
        e = new xmpp.Element('presence', { to : stanza.attrs.from, type : 'subscribed' })
        client.send e
        e = new xmpp.Element('presence', { to : stanza.attrs.from, type : 'subscribe' })
        client.send e
      when 'unsubscribe'
        console.log "Unsubscribe from " + stanza.attrs.from
        client.buddylist.setOffline stanza.attrs.from
      when 'unsubscribed'
        console.log "Unsubscribed from " + stanza.attrs.from
        client.buddylist.setOffline stanza.attrs.from
      when 'unavailable'
        console.log "Unavailable: " + stanza.attrs.from
        client.buddylist.setOffline stanza.attrs.from
      else
        return if !stanza.attrs.from.match(/\//)
        console.log "Available: " + stanza.attrs.from
        client.buddylist.setOnline stanza.attrs.from

client.on 'error', (e) ->
  console.error('Error: ' + e)

server = http.createServer( (req, res) ->
  console.log "Received HTTP request for " + req.url + " from " + req.socket.remoteAddress
  if req.url == "/"
    res.writeHead 200, {'Content-type': 'text/html'}
    res.write '<h1>The Human Powered Web Server</h1>'
    res.write '<p>Welcome to the human powered web server, type any URL in for this domain and the result will be fulfilled by a real live human.</p><p>If you would like to join the workforce, add <a href="xmpp:humanweb@jabber.org">humanweb@jabber.org</a> to your Jabber or Google Talk buddy list.</p>'
    res.write "<p>Once you have the buddy added, you'll start to receive web requests. You have 90 seconds to write a response (html or plain text is fine) and it'll be sent back to the originators web browser. Do it all on one line.</p>"
    res.write "<p>Return the message '404' to send a 404 not found response.</p>"
    res.write "<p>You can stop receiving requests by removing the user from your jabber list</p>"
    res.write '<p>It was written by <a href="http://daveverwer.com/">Dave Verwer</a> and <a href="http://johnleach.co.uk">John Leach</a> during a <a href="http://leedshack.com/">leeds hack</a> session.</p>'
    res.end "\n"
    return
  if req.url.match(/favicon.ico|robots.txt|favicon.png/)
    res.writeHead 404, {'Content-type': 'text/plain'}
    res.end 'Ignored\n'
    return
  if req.url == "/status"
    res.writeHead 200, {'Content-type': 'text/html'}
    res.write '<table>'
    for buddy in client.buddylist.online
      do (buddy) ->
        res.write '<tr><td>'+buddy+'</td><td>' + client.buddylist.status(buddy) + '</tr>'
    res.write '</table>'
    res.end '\n'
    return
  if req.headers["Referer"]
    console.log "Ignoring request with referer"
    res.writeHead 404, {'Content-type': 'text/html'}
    res.write "No referer headers please"
    res.end "\n"
    return
  msg = req.method + ' ' + req.url + "\n"
  msg += 'X-Forwarded-For: ' + req.socket.remoteAddress + "\n"
  msg += 'User Agent: ' + req.headers["user-agent"]
  client.buddylist.assignWork msg, (message) ->
    if message == '404'
      res.writeHead 404, {}
      res.end "Human sent 404\n"
      return
    res.writeHead 200, {'Content-Type': 'text/html', 'Cache-Control': 'public,max-age=600', 'Last-Modified': (new Date).toUTCString(), 'Server': 'Human'}
    res.end message + '\n'
  , (errorCode, message) ->
    res.writeHead errorCode, {'Content-Type': 'text/plain'}
    res.end message
)

server.listen 5000
