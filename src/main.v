module main

import vweb
import db.sqlite
import rand

struct App {
	vweb.Context
mut:
	db   sqlite.DB
	user User
}

struct Todo {
	id        int
	completed bool
	task      string
}

struct User {
	todos []Todo
mut:
	todo_token string
}

fn main() {
	mut app := App{
		db: sqlite.connect(':memory:')!
	}

	app.db.exec('CREATE TABLE IF NOT EXISTS todos(
					id INTEGER PRIMARY KEY,
					completed INTEGER,
					task TEXT NOT NULL,
					user_token TEXT NOT NULL
				)')!

	app.db.exec('CREATE TABLE IF NOT EXISTS users(
					id INTEGER PRIMARY KEY,
					todo_token TEXT NOT NULL
				)')!

	app.serve_static('/output.css', './css/output.css')
	app.serve_static('/made_with', './static/createdwith.jpeg')
	vweb.run(app, 8089)
}

['/']
pub fn (mut app App) index() vweb.Result {
	todos := app.get_todos(app.user.todo_token) or { []Todo{} }
	count := app.count_incomplete(app.user.todo_token)
	return $vweb.html()
}

['/new'; post]
pub fn (mut app App) new() vweb.Result {
	task := app.form['new-todo'] or { return app.text('') }
	app.db.exec_param_many('INSERT INTO todos (completed, task, user_token) VALUES (?, ?, ?)',
		['FALSE', task, app.user.todo_token]) or { panic(err) }
	todo := Todo{
		id: int(app.db.last_insert_rowid())
		completed: false
		task: task
	}
	count := app.count_incomplete(app.user.todo_token)
	return $vweb.html()
}

['/complete/:id'; post]
pub fn (mut app App) complete(id int) vweb.Result {
	res := app.db.exec_param_many('SELECT completed, task FROM todos WHERE user_token = ? AND id = ?',
		[app.user.todo_token, id.str()]) or { panic(err) }
	if res.len == 0 {
		return app.text('')
	}
	mut new_status := 'FALSE'
	if res[0].vals[0] != 'TRUE' {
		new_status = 'TRUE'
	}

	app.db.exec_param_many('UPDATE todos SET completed = ? where id = ?', [
		new_status,
		id.str(),
	]) or { panic(err) }

	todo := Todo{
		id: id
		completed: new_status == 'TRUE'
		task: res[0].vals[1]
	}
	count := app.count_incomplete(app.user.todo_token)
	return $vweb.html()
}

['/delete/:id'; delete]
pub fn (mut app App) delete(id int) vweb.Result {
	app.db.exec_param_many('DELETE FROM todos WHERE user_token = ? AND id = ?', [
		app.user.todo_token,
		id.str(),
	]) or { panic(err) }
	count := app.count_incomplete(app.user.todo_token)
	return $vweb.html()
}

['/clear-completed'; delete]
pub fn (mut app App) clearcompleted() vweb.Result {
	app.db.exec_param('DELETE FROM todos WHERE user_token = ? AND completed = "TRUE"',
		app.user.todo_token) or { panic(err) }
	todos := app.get_todos(app.user.todo_token) or { []Todo{} }
	count := app.count_incomplete(app.user.todo_token)
	return $vweb.html()
}

['/complete-all'; post]
pub fn (mut app App) completeall() vweb.Result {
	app.db.exec_param('UPDATE todos SET completed = "TRUE" WHERE user_token = ?', app.user.todo_token) or {
		panic(err)
	}
	todos := app.get_todos(app.user.todo_token) or { []Todo{} }
	return $vweb.html()
}

fn (app &App) count_incomplete(user_token string) int {
	res := app.db.exec_param('SELECT COUNT(*) FROM todos WHERE user_token = ? AND completed = "FALSE"',
		user_token) or { panic(err) }
	if res.len == 0 {
		return 0
	}
	return res[0].vals[0].int()
}

fn (app &App) get_todos(user_token string) ?[]Todo {
	rows := app.db.exec_param('SELECT * FROM todos WHERE user_token = ? ORDER BY id DESC',
		user_token) or { panic(err) }
	if rows.len == 0 {
		return none
	}
	mut todos := []Todo{}
	for row in rows {
		todo := Todo{
			id: row.vals[0].int()
			completed: row.vals[1] == 'TRUE'
			task: row.vals[2]
		}
		todos << todo
	}

	return todos
}

pub fn (mut app App) before_request() {
	user_token := app.get_cookie('user_token') or { '' }
	if user_token.len == 0 {
		new_token := rand.uuid_v4()
		app.db.exec_param('INSERT INTO users (todo_token) VALUES (?)', new_token) or { panic(err) }
		app.set_cookie(name: 'user_token', value: new_token)
	}
	app.user.todo_token = user_token
}
