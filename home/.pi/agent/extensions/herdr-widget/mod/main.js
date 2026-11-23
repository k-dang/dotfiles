import { View, div } from "gpui-kit";
import { h_flex, v_flex, ScrollHandle } from "gpui-base";
import { checking, exec, nextCommand, props, theme } from "herdr";

const errorText = error => String(error?.message ?? error).slice(0, 600);

export default class ProjectWidget extends View {
  init(_props, cx) {
    this.spec = props() ?? {};
    this.focus = cx.focus_handle();
    this.scroll = ScrollHandle.new();
    this.items = [];
    this.selected = 0;
    if (checking()) {
      this.items = [{ title: "Widget item", detail: "Example detail" }];
      return;
    }
    if (!this.spec.name) return;
    cx.spawn(async () => {
      for (;;) if (await nextCommand() === "focus") this.focus.focus();
    });
    this.refresh(cx);
    if (this.spec.refreshSeconds) cx.timer.every(this.spec.refreshSeconds * 1000, cx => this.refresh(cx, false));
  }

  async work(mode, item) {
    const args = [this.spec.worker, mode, JSON.stringify(this.spec)];
    if (item) args.push(JSON.stringify(item));
    const result = await exec(this.spec.node, args, { cwd: this.spec.root, timeout: 130000 });
    if (result.code !== 0) throw new Error("Widget worker failed to start. Reopen from Pi after updating the extension.");
    const output = JSON.parse(result.stdout);
    if (output.error) throw new Error(output.error);
    return output;
  }

  refresh(cx, manual = true) {
    if (!this.spec.name) return;
    if (this.loading || this.acting) {
      if (manual) this.refreshQueued = true;
      cx.notify();
      return;
    }
    this.loading = true;
    this.review = false;
    this.notice = "";
    cx.notify();
    cx.spawn(async cx => {
      try {
        const { items } = await this.work("refresh");
        this.items = items;
        this.select(0);
        this.error = "";
        this.updated = new Date().toLocaleTimeString();
      } catch (error) { this.error = errorText(error); }
      this.loading = false;
      this.runQueuedRefresh(cx);
    });
  }

  runQueuedRefresh(cx) {
    if (this.refreshQueued) {
      this.refreshQueued = false;
      this.refresh(cx);
    } else cx.notify();
  }

  select(index) {
    this.selected = index;
    this.review = false;
    this.notice = "";
    if (this.items.length) this.scroll.scroll_to_item(index);
  }

  action(cx) {
    if (!this.items[this.selected]) return;
    if (this.spec.action?.kind === "view") this.details = !this.details;
    else if (!this.loading && !this.error && !this.acting) this.review = true;
    cx.notify();
  }

  confirm(cx) {
    const item = this.items[this.selected];
    if (!this.review || !item || this.loading || this.error || this.acting) return;
    this.review = false;
    this.acting = true;
    this.notice = "Applying selected action…";
    cx.notify();
    cx.spawn(async cx => {
      try { this.notice = (await this.work("action", item)).message; }
      catch (error) { this.notice = errorText(error); }
      this.acting = false;
      this.runQueuedRefresh(cx);
    });
  }

  key(event, cx) {
    if (event.keystroke !== event.key) return;
    if (event.is_held && event.key !== "up" && event.key !== "down") return;
    const max = this.items.length - 1;
    if (event.key === "up" && max >= 0) this.select(Math.max(0, this.selected - 1));
    else if (event.key === "down" && max >= 0) this.select(Math.min(max, this.selected + 1));
    else if (event.key === "r") this.refresh(cx);
    else if (event.key === "enter") this.action(cx);
    else if (event.key === "d") this.details = !this.details;
    else if (event.key === "y" && this.review) this.confirm(cx);
    else if (event.key === "escape" && (this.review || this.details)) this.review = this.details = false;
    else return;
    cx.stop_propagation();
    cx.notify();
  }

  render() {
    const t = theme();
    const button = (id, label, action) => div().id(id).px(8).py(4).rounded(5).bg(t.raised)
      .hover(s => s.bg(t.hover)).cursor_pointer().on_click((_ev, cx) => { this.focus.focus(); action(cx); }).child(label);
    const text = (value, color = t.muted) => div().text_color(color).child(value);
    const kind = this.spec.action?.kind ?? "view";
    const label = kind === "view" ? "Details" : kind === "send" ? "Send to Main" : "Append to file";
    const item = this.items[this.selected];
    const status = this.loading ? (this.refreshQueued ? "Refreshing… another refresh queued" : "Gathering and judging…")
      : this.error ? (this.items.length ? "Refresh failed • showing stale items" : "Refresh failed")
      : this.updated ? `Updated ${this.updated}` : "Waiting for data";
    return v_flex().id("widget").track_focus(this.focus).on_key_down((e, cx) => this.key(e, cx))
      .on_click(() => this.focus.focus()).size_full().min_h(0).p(10).gap(6).bg(t.surface).text_color(t.foreground).text_size(13)
      .child(div().font_semibold().text_size(15).child(this.spec.name ?? "Project widget"))
      .child(text(`${this.spec.sample ? "Sample" : "Live"} • ${this.spec.refreshSeconds ? `Every ${this.spec.refreshSeconds}s` : "Manual"} • ${status}`))
      .when(!!this.error, el => el.child(text(this.error, t.blocked)))
      .child(v_flex().id("items").h(Math.min(240, Math.max(1, this.items.length) * 34)).min_h(0).overflow_y_scrollbar().track_scroll(this.scroll).gap(2)
        .when(!this.items.length && !this.loading && !this.error, el => el.child(text("No items match.")))
        .children(this.items.map((row, index) => div().id(`item-${index}`).p(6).rounded(4)
          .bg(index === this.selected ? t.selected : t.surface).hover(s => s.bg(t.hover)).cursor_pointer()
          .on_click((_ev, cx) => { this.focus.focus(); this.select(index); cx.notify(); }).child(div().truncate().child(row.title)))))
      .child(text(`↑/↓ Select · D Details · Enter ${kind === "view" ? "Details" : `Review ${label.toLowerCase()}`} · R Refresh`))
      .child(h_flex().gap(6)
        .child(button("refresh", "Refresh (R)", cx => this.refresh(cx)))
        .when(!!item && (kind === "view" || (!this.loading && !this.error && !this.acting)), el => el
          .child(button("action", kind === "view" ? label : `Review: ${label}`, cx => this.action(cx)))))
      .when(!!item && (this.review || this.details), el => el.child(v_flex().id("details").max_h(155).min_h(0)
        .overflow_y_scrollbar().bg(t.background).rounded(6).p(8).gap(4)
        .child(div().font_semibold().child(item.title)).child(text(item.detail, t.foreground))))
      .when(!!this.review, el => el.child(text(kind === "send" ? "Submit the item to the original Main Pi session?" : `Append this item to ${this.spec.action.file}?`))
        .child(h_flex().gap(6).child(button("confirm", `Confirm ${label.toLowerCase()} (Y)`, cx => this.confirm(cx)))
          .child(button("cancel", "Cancel (Esc)", cx => { this.review = false; cx.notify(); }))))
      .when(!!this.notice, el => el.child(text(this.notice)));
  }
}
