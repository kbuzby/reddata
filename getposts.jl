import JSON
import Requests
import SQLite
using Gadfly
using Gumbo

url = "http://www.reddit.com/r/all/.json"
req = get(url)
posts = JSON.parse(req.data)["data"]["children"]

db = SQLite.SQLiteDB("/home/kyle/dev/reddata/postdb")

Top5Posts = map((post) -> post["data"], posts[1:5])

#determine if the top5 is a fresh top 5
freshset = true
for post in Top5Posts
	title = replace(post["title"],['\'','"'],"")
	test = SQLite.query(db, "SELECT title FROM Top5Posts WHERE title='$(title)'")
	if test[1][1] == title
		freshset = false
		break
	end
end

#delete previous top5 from table, and set time of update
if freshset
	SQLite.query(db, "DELETE FROM Top5Posts")
	SQLite.query(db, "INSERT INTO refreshes VALUES('$(Dates.datetime2unix(Dates.now()))')")
end


i = 1
for post in Top5Posts
	#get desired values
	title = replace(post["title"],['\'','"'],"")
	author = replace(post["author"],['\'','"'],"")
	sub = replace(post["subreddit"],['\'','"'],"")
	created = post["created_utc"]
	score = post["score"]
	nsfw = convert(Int32, post["over_18"])

	if freshset 
		SQLite.query(db, "INSERT INTO Top5Posts VALUES(null,'$(title)','$(author)','$(sub)','$(created)','$(score)','$(nsfw)')")
	end

	#check if post exists
	postexists = false
	test = SQLite.query(db, "SELECT title FROM AllPosts WHERE title='$(title)'")
	if test[1][1] == title
		postexists = true
	end

	if postexists
		pdata = SQLite.query(db, "SELECT topRank,topScore FROM AllPosts WHERE title='$(title)'")
		curRank = pdata[1][1]
		curScore = pdata[2][1]
		if curRank > i
			SQLite.query(db, "UPDATE AllPosts SET topRank=$i WHERE title='$(title)'")
		end
		if curScore > score
			SQLite.query(db, "UPDATE AllPosts SET topScore=$(score) WHERE title='$(title)'")
		end
	else
		SQLite.query(db, "INSERT INTO AllPosts VALUES($i,'$(title)','$(author)','$(sub)','$(created)','$(score)','$(nsfw)')")
	end
	i += 1
end

#Get average refresh times
times = SQLite.query(db, "SELECT * FROM refreshes")
tdifs = map((x,y) -> int(Dates.unix2datetime(y) - Dates.unix2datetime(x)), times[1][1:end-1], times[1][2:end])
mtime = mean(tdifs)/(1000*60*60)

q = SQLite.query(db, "SELECT subreddit, COUNT(1) as 'num' FROM AllPosts GROUP BY subreddit ORDER By COUNT(1)")
p = plot(x=q[1],y=q[2],Geom.bar,Guide.xlabel("subreddit"),Guide.ylabel("# of Top 5 Posts"))
draw(SVGJS("/home/kyle/dev/reddata/topsubs.js.svg", 8inch, 6inch), p)

scribs = ones(Int64,length(q[2]))
for (index,sub) in enumerate(q[1])
	url = "http://www.reddit.com/r/$sub/about.json"
	req = get(url)
	scribs[index] = int(JSON.parse(req.data)["data"]["subscribers"])
end
nscribs = map(/,q[2],scribs)

p = plot(x=q[1],y=nscribs,Geom.bar,Guide.xlabel("subreddit"),Guide.ylabel("# of Top 5 Posts / Subscribers"))
draw(SVGJS("/home/kyle/dev/reddata/ntopsubs.js.svg",8inch,6inch),p)
	

#Manipulate HTML file
f = open("/var/www/html/reddata/top5subs.html")
fstr = readall(f)
close(f)
htmldoc = parsehtml(fstr)
for elem in postorder(htmldoc.root)
	if typeof(elem) == HTMLElement{:p}
		elid = attrs(elem)["id"]
		if elid == "meantime"
			pop!(elem)
			push!(elem, HTMLText("It takes an average of $(round(mtime,2)) hours to see a new Top 5"))
		end
		if elid == "updated"
			pop!(elem)
			push!(elem, HTMLText("Last updated $(now())"))
		end
	end
end
f = open("/var/www/html/reddata/top5subs.html","w")
print(f,htmldoc)
close(f)

SQLite.close(db)
