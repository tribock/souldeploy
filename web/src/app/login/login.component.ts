import { Component } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from '../auth.service';
import { FormsModule } from '@angular/forms';
import { ClarityModule } from '@clr/angular';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-login',
  templateUrl: './login.component.html',
  styleUrls: ['./login.component.scss'],
  standalone: true,
  imports: [FormsModule, ClarityModule, CommonModule]
})
export class LoginComponent {
  username: string;
  password: string;
  errorMessage: string;

  constructor(private authService: AuthService, private router: Router) {}

  form = {
    type: 'local',
    username: '',
    password: '',
    rememberMe: false,
  };

  login() {

    this.authService.login(this.form.username, this.form.password).subscribe(
      (resp: any) => {

          console.log('Login successful');
          localStorage.setItem('username', this.form.username); // Store the username
        
          this.router.navigate(['/']);
    
      },
      (error) => {
        console.log(error);
        this.errorMessage = "Invalid username or password";
        this.router.navigate(['/login']);
      }
    );

  }
}

