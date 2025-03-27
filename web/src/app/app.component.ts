import { Component, OnInit } from '@angular/core';
import { ApiService } from './api.service';
import { Router } from '@angular/router';
import { AuthService } from './auth.service';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.scss'],
  standalone: false
})
export class AppComponent implements OnInit {
  version: any;
  username: string;
  showAbout: boolean = false;

  constructor(private apiService: ApiService, public router: Router, private authService: AuthService) {}

  ngOnInit(): void {

    this.authService.username$.subscribe(username => {
      this.username = username;
    });

    this.apiService.getVersion().subscribe((data: any) => {
      this.version = data;
      console.log(this.version);
    });

    if (!this.authService.isLoggedIn()) {
      this.username = null;
      this.router.navigate(['/login']);
    }
  }

  logout() {
    this.authService.logout();
    this.username = null;
  }

  showAboutModel(mode, id=null) {
    this.showAbout = mode;

  }
}


