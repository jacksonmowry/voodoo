module main

import vweb

struct App {
	vweb.Context
}

fn main() {
	mut app := App{}
	app.serve_static('/output.css', './css/output.css')
	vweb.run(app, 8088)
}

['/']
pub fn (mut app App) index() vweb.Result {
	return $vweb.html()
}
