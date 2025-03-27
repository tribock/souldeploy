import { Component } from '@angular/core';
import { HostDeploymentComponent } from './host-deployment.component';

@Component({
  selector: 'app-wizard',
  imports: [HostDeploymentComponent],
  templateUrl: './wizard.component.html',
  styleUrl: './wizard.component.scss'
})
export class WizardComponent {

}
